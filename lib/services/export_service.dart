import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_models.dart';
import 'database_service.dart';

class ExportService {
  // حفظ ملف JSON في مجلد يختاره المستخدم أو مشاركته
  static Future<String?> exportJsonToFile({bool askLocation = true}) async {
    final jsonContent = await DatabaseService.instance.exportFullBackupJson();
    final fileName = 'debt_book_backup_${intl.DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';

    if (askLocation) {
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'اختر مكان حفظ النسخة الاحتياطية',
        fileName: fileName,
        bytes: Uint8List.fromList(jsonContent.codeUnits),
      );
      if (outputPath != null) {
        final file = File(outputPath);
        await file.writeAsString(jsonContent);
        return outputPath;
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonContent);
    return file.path;
  }

  // استيراد ملف JSON والتحقق من سلامته
  static Future<bool> importJsonFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return false;
    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    return await DatabaseService.instance.importFullBackupJson(content);
  }

  // تصدير البيانات إلى ملف Excel ومشاركته
  static Future<void> exportToExcel(List<DebtItem> debts, String currency, String reportTitle) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['التقرير المالي'];
    excel.delete('Sheet1');

    sheet.appendRow([
      TextCellValue('الاسم'),
      TextCellValue('رقم الهاتف'),
      TextCellValue('النوع'),
      TextCellValue('المبلغ الأصلي ($currency)'),
      TextCellValue('المدفوع ($currency)'),
      TextCellValue('المتبقي ($currency)'),
      TextCellValue('الحالة'),
      TextCellValue('التاريخ'),
      TextCellValue('الملاحظات'),
    ]);

    for (var d in debts) {
      sheet.appendRow([
        TextCellValue(d.personName),
        TextCellValue(d.phone),
        TextCellValue(d.isForMe ? 'دين لي' : 'دين عليّ'),
        DoubleCellValue(d.amount),
        DoubleCellValue(d.paidAmount),
        DoubleCellValue(d.remainingAmount),
        TextCellValue(d.isFullyPaid ? 'مسدد' : (d.isPartiallyPaid ? 'جزئي' : 'غير مسدد')),
        TextCellValue(intl.DateFormat('yyyy/MM/dd').format(d.date)),
        TextCellValue(d.note),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${reportTitle}_${DateTime.now().millisecondsSinceEpoch}.xlsx');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles([XFile(file.path)], text: reportTitle);
  }

  // إنشاء تقرير PDF عربي احترافي ومشاركته/طباعته
  static Future<void> generateAndSharePdf({
    required List<DebtItem> debts,
    required String currency,
    required String title,
  }) async {
    final pdf = pw.Document();
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();

    final totalForMe = debts.where((d) => d.isForMe).fold(0.0, (s, d) => s + d.remainingAmount);
    final totalOnMe = debts.where((d) => !d.isForMe).fold(0.0, (s, d) => s + d.remainingAmount);
    final net = totalForMe - totalOnMe;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0F766E'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(title, style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text(intl.DateFormat('yyyy/MM/dd').format(DateTime.now()),
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 12)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _pdfSummaryBox('المتبقي لك', '${totalForMe.toStringAsFixed(0)} $currency', PdfColors.green700),
              _pdfSummaryBox('المتبقي عليك', '${totalOnMe.toStringAsFixed(0)} $currency', PdfColors.red700),
              _pdfSummaryBox('الصافي', '${net.toStringAsFixed(0)} $currency', PdfColors.teal800),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['التاريخ', 'الحالة', 'المتبقي', 'المدفوع', 'الأصلي', 'النوع', 'الاسم'],
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#0F766E')),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.center,
            data: debts.map((d) {
              return [
                intl.DateFormat('yyyy/MM/dd').format(d.date),
                d.isFullyPaid ? 'مسدد' : (d.isPartiallyPaid ? 'جزئي' : 'مفتوح'),
                d.remainingAmount.toStringAsFixed(0),
                d.paidAmount.toStringAsFixed(0),
                d.amount.toStringAsFixed(0),
                d.isForMe ? 'لك' : 'عليك',
                d.personName,
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${title}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _pdfSummaryBox(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(color: color, fontWeight: pw.FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}
