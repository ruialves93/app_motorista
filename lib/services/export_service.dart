import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/driver_entry.dart';
import 'db_helper.dart';

class ExportService {
  static String formatDuration(double decimalHours) {
    if (decimalHours <= 0.001) return '00:00';
    int totalMinutes = (decimalHours * 60).round();
    int h = totalMinutes ~/ 60;
    int m = totalMinutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static String formatCurrency(double val) {
    return '${val.toStringAsFixed(2)} €';
  }

  static double round2(double val) {
    return double.parse(val.toStringAsFixed(2));
  }

  static Future<pw.ImageProvider?> _loadLogoProvider() async {
    try {
      final bytes = await rootBundle.load('assets/logo_rb.png');
      return pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _calcDayRow(
    DriverEntry e,
    double vhNormal,
    double vhRest,
    Map<String, double> rates,
    String driverType,
  ) {
    double h50 = 0.0;
    double h75 = 0.0;
    double h200 = 0.0;
    double h300 = 0.0;
    double pay50 = 0.0;
    double pay75 = 0.0;
    double pay200 = 0.0;
    double pay300 = 0.0;
    double nightPay = 0.0;
    double mealsPay = 0.0;
    double dailyCollectionPay = 0.0;
    int mealsCount = 0;

    if (e.dayType == 'Util') {
      double ot = e.overtimeHours;
      if (ot > 0) {
        h50 = ot >= 1.0 ? 1.0 : ot;
        h75 = ot > 1.0 ? ot - 1.0 : 0.0;
        pay50 = h50 * vhNormal * 1.50;
        pay75 = h75 * vhNormal * 1.75;
      }
    } else if (e.dayType == 'Descanso' || e.dayType == 'Feriado') {
      double hours = e.regularHours + e.overtimeHours;
      if (hours > 0) {
        h200 = hours < 5.0 ? 5.0 : (hours > 8.0 ? 8.0 : hours);
        h300 = hours > 8.0 ? hours - 8.0 : 0.0;
        pay200 = h200 * vhRest * 2.00;
        pay300 = h300 * vhRest * 3.00;
      }
    }

    if (e.nightHours > 0) {
      nightPay = e.nightHours * (vhNormal * 0.25);
    }

    if (driverType == 'Turismo' &&
        e.hasCollection &&
        (e.dayType == 'Util' || e.dayType == 'Descanso' || e.dayType == 'Feriado')) {
      dailyCollectionPay = vhNormal * 8.0 * 0.20;
    }

    if (e.dayType != 'Baixa' &&
        e.dayType != 'Falta' &&
        e.dayType != 'Folga' &&
        e.dayType != 'Ferias') {
      if (e.hasMealAllowance) {
        mealsPay += rates['mealAllowance'] ?? 5.50;
        mealsCount += 1;
      } else {
        if (e.firstMeal == 'Normal') {
          mealsPay += rates['firstMealNormal'] ?? 10.00;
          mealsCount += 1;
        } else if (e.firstMeal == 'Penalizada') {
          mealsPay += rates['firstMealPenalized'] ?? 5.80;
          mealsCount += 1;
        }
        if (e.secondMeal == 'Normal') {
          mealsPay += rates['secondMealNormal'] ?? 7.00;
          mealsCount += 1;
        } else if (e.secondMeal == 'Penalizada') {
          mealsPay += rates['secondMealPenalized'] ?? 2.20;
          mealsCount += 1;
        }
      }
    }

    double dayTotalEuro = pay50 + pay75 + pay200 + pay300 + nightPay + mealsPay + dailyCollectionPay;

    return {
      'h50': h50,
      'h75': h75,
      'h200': h200,
      'h300': h300,
      'pay50': round2(pay50),
      'pay75': round2(pay75),
      'pay200': round2(pay200),
      'pay300': round2(pay300),
      'nightPay': round2(nightPay),
      'mealsPay': round2(mealsPay),
      'mealsCount': mealsCount,
      'dailyCollectionPay': round2(dailyCollectionPay),
      'dayTotalEuro': round2(dayTotalEuro),
    };
  }

  // ==========================================
  // 1. FOLHA DE SERVIÇO (PDF)
  // ==========================================
  static Future<Uint8List> _generatePdfBytes({
    required String periodTitle,
    required String driverName,
    required String driverNif,
    required String companyName,
    required String companyNif,
    required String driverType,
    required List<DriverEntry> entryList,
    required Map<String, double> rates,
    required Map<String, double> totals,
    required String generationFormattedDate,
  }) async {
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontMedium = await PdfGoogleFonts.robotoMedium();
    final fontItalic = await PdfGoogleFonts.robotoItalic();

    final logo = await _loadLogoProvider();

    final pdf = pw.Document(
      title: 'Folha de Servico CCTV - $driverName ($periodTitle)',
      author: 'Rui Barata - CCTV Motorista',
      creator: 'CCTV Motorista App (BTE 29/2022)',
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold, italic: fontItalic),
    );

    final baseSalary = rates['baseSalary'] ?? 942.00;
    final vhNormal = rates['vhNormal'] ?? ((baseSalary * 12) / (40 * 52));
    final vhRest = rates['vhRest'] ?? ((baseSalary / 30) / 8);
    final dailyDeduction = baseSalary / 30;

    double sumH50 = 0, sumPay50 = 0;
    double sumH75 = 0, sumPay75 = 0;
    double sumH200 = 0, sumPay200 = 0;
    double sumH300 = 0, sumPay300 = 0;
    double sumHNight = 0, sumPayNight = 0;
    double sumIntermitencia = 0;
    double sumMeals = 0;
    int totalMealsCount = 0;

    int folgasCount = 0;
    int feriasCount = 0;
    int baixasCount = 0;
    int faltasCount = 0;
    int collectionDaysCount = 0;
    double sumDailyCollectionPay = 0;

    List<List<String>> tableData = [];

    for (var e in entryList) {
      final calc = _calcDayRow(e, vhNormal, vhRest, rates, driverType);

      sumH50 += calc['h50'];
      sumPay50 += calc['pay50'];
      sumH75 += calc['h75'];
      sumPay75 += calc['pay75'];
      sumH200 += calc['h200'];
      sumPay200 += calc['pay200'];
      sumH300 += calc['h300'];
      sumPay300 += calc['pay300'];
      sumHNight += e.nightHours;
      sumPayNight += calc['nightPay'];
      sumIntermitencia += e.intermitenciaHours;
      sumMeals += calc['mealsPay'];
      totalMealsCount += (calc['mealsCount'] as int);

      if (calc['dailyCollectionPay'] > 0) {
        collectionDaysCount++;
        sumDailyCollectionPay += calc['dailyCollectionPay'];
      }

      if (e.dayType == 'Folga') folgasCount++;
      if (e.dayType == 'Ferias') feriasCount++;
      if (e.dayType == 'Baixa') baixasCount++;
      if (e.dayType == 'Falta') faltasCount++;

      String refStr = '-';
      if (e.hasMealAllowance) {
        refStr = 'S.Alim';
      } else {
        List<String> r = [];
        if (e.firstMeal != 'Nenhuma') r.add('1ª:${e.firstMeal[0]}');
        if (e.secondMeal != 'Nenhuma') r.add('2ª:${e.secondMeal[0]}');
        if (r.isNotEmpty) refStr = r.join(' ');
      }

      String tipoAbrev = e.dayType;
      if (e.dayType == 'Descanso') tipoAbrev = 'Desc.Tr.';
      if (e.dayType == 'Ferias') tipoAbrev = 'Férias';

      tableData.add([
        e.date.length >= 10 ? e.date.substring(8, 10) : e.date,
        tipoAbrev,
        e.startTime.isNotEmpty ? e.startTime : '-',
        e.endTime.isNotEmpty ? e.endTime : '-',
        formatDuration(e.regularHours),
        formatDuration(calc['h50']),
        formatDuration(calc['h75']),
        formatDuration(calc['h200']),
        formatDuration(calc['h300']),
        formatDuration(e.nightHours),
        formatDuration(e.intermitenciaHours),
        refStr,
        calc['pay50'] > 0 ? '${calc['pay50'].toStringAsFixed(2)} €' : '-',
        calc['pay75'] > 0 ? '${calc['pay75'].toStringAsFixed(2)} €' : '-',
        calc['pay200'] > 0 ? '${calc['pay200'].toStringAsFixed(2)} €' : '-',
        calc['pay300'] > 0 ? '${calc['pay300'].toStringAsFixed(2)} €' : '-',
        calc['nightPay'] > 0 ? '${calc['nightPay'].toStringAsFixed(2)} €' : '-',
        calc['mealsPay'] > 0 ? '${calc['mealsPay'].toStringAsFixed(2)} €' : '-',
      ]);
    }

    final double valorBaixas = baixasCount * dailyDeduction;
    final double valorFaltas = faltasCount * dailyDeduction;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logo != null)
                      pw.Container(
                        width: 36,
                        height: 36,
                        margin: const pw.EdgeInsets.only(right: 8),
                        child: pw.Image(logo),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName.isNotEmpty ? companyName.toUpperCase() : 'FOLHA DE SERVIÇO CCTV MOTORISTA',
                          style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.blueGrey900),
                        ),
                        if (companyNif.isNotEmpty)
                          pw.Text('NIF Empresa: $companyNif', style: pw.TextStyle(font: fontRegular, fontSize: 8, color: PdfColors.grey700)),
                        pw.Text(
                          'Enquadramento: CCTV ANTROP (BTE 29/2022) | Regime: ${driverType == "Turismo" ? "Comercial / Turismo" : "Serviço Público"}',
                          style: pw.TextStyle(font: fontMedium, fontSize: 7.5, color: PdfColors.blueGrey600),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Mês / Período: $periodTitle',
                        style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: PdfColors.teal800)),
                    pw.Text('Motorista: $driverName',
                        style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    if (driverNif.isNotEmpty)
                      pw.Text('NIF: $driverNif', style: pw.TextStyle(font: fontRegular, fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Table.fromTextArray(
              headers: [
                'Dia',
                'Tipo',
                'Início',
                'Fim',
                'H. Norm\n(8H)',
                'H. 50%',
                'H. 75%',
                'H. 200%',
                'H. 300%',
                'H. Not.',
                'Interm.',
                'Refeições',
                'H. 50%\n(€)',
                'H. 75%\n(€)',
                'H. 200%\n(€)',
                'H. 300%\n(€)',
                'H. Not.\n(€)',
                'Refeições\n(€)',
              ],
              data: tableData,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerStyle: pw.TextStyle(font: fontBold, fontSize: 6.2, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E293B)),
              cellStyle: pw.TextStyle(font: fontRegular, fontSize: 6.2),
              cellAlignment: pw.Alignment.center,
              oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC)),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 1.8, vertical: 1.8),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF1F5F9),
                border: pw.TableBorder.all(color: PdfColors.blueGrey300, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'RESUMO DE VENCIMENTOS E VARIÁVEIS (BTE 29/2022)',
                        style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.blueGrey900),
                      ),
                      pw.Text(
                        'Total Bruto Estimado: ${(totals['gross'] ?? 0.0).toStringAsFixed(2)} €',
                        style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.teal900),
                      ),
                    ],
                  ),
                  pw.Divider(color: PdfColors.blueGrey300, thickness: 0.5),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('• Vencimento Base: ${baseSalary.toStringAsFixed(2)} €',
                                style: pw.TextStyle(font: fontBold, fontSize: 7.4, color: PdfColors.blueGrey900)),
                            pw.SizedBox(height: 2),
                            if (driverType == 'Publico')
                              pw.Text('• Cobrança Incluída (20%): ${(totals['includedCollection'] ?? 0).toStringAsFixed(2)} €',
                                  style: pw.TextStyle(font: fontMedium, fontSize: 7.2, color: PdfColors.indigo900))
                            else
                              pw.Text('• Cobrança Diária: $collectionDaysCount d (+${sumDailyCollectionPay.toStringAsFixed(2)} €)',
                                  style: pw.TextStyle(font: fontMedium, fontSize: 7.2, color: PdfColors.indigo900)),
                            pw.SizedBox(height: 2),
                            pw.Text('• Folgas Gozadas: $folgasCount dias',
                                style: pw.TextStyle(font: fontMedium, fontSize: 7.2, color: PdfColors.blue800)),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('• Total H. 50%: ${formatDuration(sumH50)} (${sumPay50.toStringAsFixed(2)} €)',
                                style: pw.TextStyle(font: fontRegular, fontSize: 7.2)),
                            pw.SizedBox(height: 2),
                            pw.Text('• Total H. 75%: ${formatDuration(sumH75)} (${sumPay75.toStringAsFixed(2)} €)',
                                style: pw.TextStyle(font: fontRegular, fontSize: 7.2)),
                            pw.SizedBox(height: 2),
                            pw.Text('• Férias Gozadas: $feriasCount dias',
                                style: pw.TextStyle(font: fontMedium, fontSize: 7.2, color: PdfColors.teal800)),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('• Total H. 200%: ${formatDuration(sumH200)} (${sumPay200.toStringAsFixed(2)} €)',
                                style: pw.TextStyle(font: fontRegular, fontSize: 7.2)),
                            pw.SizedBox(height: 2),
                            pw.Text('• Total H. 300%: ${formatDuration(sumH300)} (${sumPay300.toStringAsFixed(2)} €)',
                                style: pw.TextStyle(font: fontRegular, fontSize: 7.2)),
                            pw.SizedBox(height: 2),
                            pw.Text('• Dias de Baixa: $baixasCount d (-${valorBaixas.toStringAsFixed(2)} €)',
                                style: pw.TextStyle(font: fontMedium, fontSize: 7.2, color: baixasCount > 0 ? PdfColors.orange900 : PdfColors.grey700)),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('• Total H. Noturnas: ${formatDuration(sumHNight)} (${sumPayNight.toStringAsFixed(2)} €)',
                                style: pw.TextStyle(font: fontRegular, fontSize: 7.2)),
                            pw.SizedBox(height: 2),
                            pw.Text('• Refeições/Sub. Alim.: $totalMealsCount un. (${sumMeals.toStringAsFixed(2)} €)',
                                style: pw.TextStyle(font: fontRegular, fontSize: 7.2)),
                            pw.SizedBox(height: 2),
                            pw.Text('• Faltas: $faltasCount d (-${valorFaltas.toStringAsFixed(2)} €)',
                                style: pw.TextStyle(font: fontMedium, fontSize: 7.2, color: faltasCount > 0 ? PdfColors.red800 : PdfColors.grey700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Declaração: Os dados constantes deste documento são da exclusiva responsabilidade do utilizador.',
                        style: pw.TextStyle(font: fontBold, fontSize: 6.8, color: PdfColors.red900)),
                    pw.Text('Documento não editável emitido pela aplicação CCTV Motorista',
                        style: pw.TextStyle(font: fontRegular, fontSize: 6.6, color: PdfColors.grey800)),
                    pw.Text('Desenvolvido por: Rui Barata © 2026 | Enquadramento BTE 29/2022',
                        style: pw.TextStyle(font: fontRegular, fontSize: 6.4, color: PdfColors.grey700)),
                    pw.Text('Gerado em: $generationFormattedDate',
                        style: pw.TextStyle(font: fontItalic, fontSize: 6.4, color: PdfColors.grey600)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(height: 24, width: 240),
                    pw.Container(
                      width: 240,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text('Assinatura do Motorista: $driverName', style: pw.TextStyle(font: fontBold, fontSize: 8)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> previewAndExportPDF({
    required BuildContext context,
    required String periodTitle,
    required String driverName,
    required String driverNif,
    required String companyName,
    required String companyNif,
    required String driverType,
    required List<DriverEntry> entryList,
    required Map<String, double> rates,
    required Map<String, double> totals,
  }) async {
    final now = DateTime.now();
    final timestampForFileName = DateFormat('yyyyMMdd_HHmmss').format(now);
    final generationFormattedDate = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);

    final cleanDriver = driverName.trim().replaceAll(' ', '_');
    final cleanPeriod = periodTitle.replaceAll('/', '_');
    final fileName = 'CCTV_Motorista_${cleanDriver}_${cleanPeriod}_$timestampForFileName.pdf';

    final pdfBytes = await _generatePdfBytes(
      periodTitle: periodTitle,
      driverName: driverName,
      driverNif: driverNif,
      companyName: companyName,
      companyNif: companyNif,
      driverType: driverType,
      entryList: entryList,
      rates: rates,
      totals: totals,
      generationFormattedDate: generationFormattedDate,
    );

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blueGrey),
              title: const Text('Visualizar e Imprimir PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Pré-visualização e impressão direta'),
              onTap: () async {
                Navigator.pop(ctx);
                await Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: fileName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline, color: Colors.teal),
              title: const Text('Descarregar / Guardar no Telemóvel', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Guardar o ficheiro PDF no armazenamento'),
              onTap: () async {
                Navigator.pop(ctx);
                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/$fileName');
                await file.writeAsBytes(pdfBytes);

                final savePath = await FilePicker.platform.saveFile(
                  dialogTitle: 'Escolha onde guardar o PDF',
                  fileName: fileName,
                  type: FileType.custom,
                  allowedExtensions: ['pdf'],
                  bytes: pdfBytes,
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(savePath != null ? 'PDF guardado com sucesso!' : 'Ficheiro guardado em: ${file.path}'),
                      backgroundColor: Colors.teal[800],
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.indigo),
              title: const Text('Partilhar PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Enviar via WhatsApp, E-mail ou Drive'),
              onTap: () async {
                Navigator.pop(ctx);
                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/$fileName');
                await file.writeAsBytes(pdfBytes);

                await Share.shareXFiles([XFile(file.path)], text: 'Folha de Serviço CCTV ANTROP - $driverName ($periodTitle)');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 2. EXPORTAR EXCEL (.XLSX) COM HORAS E VALORES (€)
  // ==========================================
  static Future<Uint8List> _generateExcelBytes({
    required String periodTitle,
    required String driverName,
    required String driverNif,
    required String companyName,
    required String companyNif,
    required String driverType,
    required List<DriverEntry> entryList,
    required Map<String, double> rates,
    required Map<String, double> totals,
    required String generationFormattedDate,
  }) async {
    final excel = xl.Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Folha1';
    final sheet = excel[sheetName];

    final baseSalary = rates['baseSalary'] ?? 942.00;
    final vhNormal = rates['vhNormal'] ?? ((baseSalary * 12) / (40 * 52));
    final vhRest = rates['vhRest'] ?? ((baseSalary / 30) / 8);

    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        xl.TextCellValue('MAPA MENSAL DE SERVIÇO E VENCIMENTOS CCTV ANTROP');
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
        xl.TextCellValue('Período: $periodTitle | Motorista: $driverName (NIF: $driverNif)');
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value =
        xl.TextCellValue('Empresa: $companyName (NIF: $companyNif) | Regime: ${driverType == "Turismo" ? "Comercial / Turismo" : "Serviço Público"}');

    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value = xl.TextCellValue('Vencimento Base:');
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3)).value = xl.TextCellValue(formatCurrency(baseSalary));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 3)).value = xl.TextCellValue('VH Normal:');
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 3)).value = xl.TextCellValue(formatCurrency(vhNormal));

    final headers = [
      'Dia', 'Tipo', 'Início', 'Fim', 'H. Norm (8h)', 'H. 50%', 'H. 75%', 'H. 200%',
      'H. 300%', 'H. Not.', 'Interm.', 'Refeições', 'H. 50% (€)', 'H. 75% (€)',
      'H. 200% (€)', 'H. 300% (€)', 'H. Not. (€)', 'Refeições (€)', 'Total Dia (€)'
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5));
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = xl.CellStyle(
        bold: true,
        horizontalAlign: xl.HorizontalAlign.Center,
        backgroundColorHex: xl.ExcelColor.fromHexString('#1E293B'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
      );
    }

    double totHNorm = 0, totH50 = 0, totH75 = 0, totH200 = 0, totH300 = 0, totHNight = 0, totInterm = 0;
    double totPay50 = 0, totPay75 = 0, totPay200 = 0, totPay300 = 0, totNightPay = 0, totMealsPay = 0, totDia = 0;
    int rowIndex = 6;

    for (var e in entryList) {
      final calc = _calcDayRow(e, vhNormal, vhRest, rates, driverType);

      totHNorm += e.regularHours;
      totH50 += calc['h50'];
      totH75 += calc['h75'];
      totH200 += calc['h200'];
      totH300 += calc['h300'];
      totHNight += e.nightHours;
      totInterm += e.intermitenciaHours;

      totPay50 += (calc['pay50'] as double);
      totPay75 += (calc['pay75'] as double);
      totPay200 += (calc['pay200'] as double);
      totPay300 += (calc['pay300'] as double);
      totNightPay += (calc['nightPay'] as double);
      totMealsPay += (calc['mealsPay'] as double);
      totDia += (calc['dayTotalEuro'] as double);

      String refStr = '-';
      if (e.hasMealAllowance) {
        refStr = 'Sub. Alim.';
      } else {
        List<String> r = [];
        if (e.firstMeal != 'Nenhuma') r.add('1ª ${e.firstMeal}');
        if (e.secondMeal != 'Nenhuma') r.add('2ª ${e.secondMeal}');
        if (r.isNotEmpty) refStr = r.join(' + ');
      }

      final isEven = (rowIndex % 2 == 0);
      final rowBgColor = isEven ? '#F8FAFC' : '#FFFFFF';

      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = xl.TextCellValue(e.date);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value = xl.TextCellValue(e.dayType);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value = xl.TextCellValue(e.startTime.isNotEmpty ? e.startTime : '-');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value = xl.TextCellValue(e.endTime.isNotEmpty ? e.endTime : '-');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(e.regularHours));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(calc['h50']));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(calc['h75']));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(calc['h200']));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(calc['h300']));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(e.nightHours));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(e.intermitenciaHours));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIndex)).value = xl.TextCellValue(refStr);

      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(calc['pay50']));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(calc['pay75']));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(calc['pay200']));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(calc['pay300']));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(calc['nightPay']));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(calc['mealsPay']));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 18, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(calc['dayTotalEuro']));

      for (int c = 0; c < 19; c++) {
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).cellStyle = xl.CellStyle(
          backgroundColorHex: xl.ExcelColor.fromHexString(rowBgColor),
        );
      }

      rowIndex++;
    }

    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = xl.TextCellValue('TOTAIS');
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(totHNorm));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(totH50));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(totH75));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(totH200));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(totH300));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(totHNight));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIndex)).value = xl.TextCellValue(formatDuration(totInterm));

    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(totPay50));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(totPay75));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(totPay200));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(totPay300));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(totNightPay));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(totMealsPay));
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 18, rowIndex: rowIndex)).value = xl.TextCellValue(formatCurrency(totDia));

    for (int c = 0; c < 19; c++) {
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).cellStyle = xl.CellStyle(
        bold: true,
        backgroundColorHex: xl.ExcelColor.fromHexString('#E2E8F0'),
      );
    }

    rowIndex += 2;
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
        xl.TextCellValue('INFORMAÇÃO DE AUDITORIA E CONTROLO');
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).cellStyle =
        xl.CellStyle(bold: true);

    rowIndex++;
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
        xl.TextCellValue('Aplicação: CCTV Motorista | Enquadramento: BTE 29/2022 (ANTROP)');
    rowIndex++;
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
        xl.TextCellValue('Criador: Rui Barata © 2026');
    rowIndex++;
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
        xl.TextCellValue('Data e Hora de Geração: $generationFormattedDate');
    rowIndex++;
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
        xl.TextCellValue('Declaração: Os dados constantes deste mapa são da exclusiva responsabilidade do utilizador.');

    final bytes = excel.save();
    return Uint8List.fromList(bytes!);
  }

  static Future<void> previewAndExportExcel({
    required BuildContext context,
    required String periodTitle,
    required String driverName,
    required String driverNif,
    required String companyName,
    required String companyNif,
    required String driverType,
    required List<DriverEntry> entryList,
    required Map<String, double> rates,
    required Map<String, double> totals,
  }) async {
    if (driverName.trim().isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Nome Obrigatório'),
            ],
          ),
          content: const Text(
            'É obrigatório definir o Nome do Motorista antes de gerar o mapa em Excel.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final now = DateTime.now();
      final timestampForFileName = DateFormat('yyyyMMdd_HHmmss').format(now);
      final generationFormattedDate = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);

      final cleanDriver = driverName.trim().replaceAll(' ', '_');
      final cleanPeriod = periodTitle.replaceAll('/', '_');
      final fileName = 'CCTV_Excel_${cleanDriver}_${cleanPeriod}_$timestampForFileName.xlsx';

      final excelBytes = await _generateExcelBytes(
        periodTitle: periodTitle,
        driverName: driverName,
        driverNif: driverNif,
        companyName: companyName,
        companyNif: companyNif,
        driverType: driverType,
        entryList: entryList,
        rates: rates,
        totals: totals,
        generationFormattedDate: generationFormattedDate,
      );

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(excelBytes);

      if (!context.mounted) return;

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.table_chart, color: Colors.green),
                title: const Text('Visualizar / Abrir Excel', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Abrir com Microsoft Excel, Sheets ou WPS'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final result = await OpenFilex.open(tempFile.path);
                  if (result.type != ResultType.done && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Não foi encontrada nenhuma app compatível. Mensagem: ${result.message}'),
                        backgroundColor: Colors.orange[800],
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_for_offline, color: Colors.teal),
                title: const Text('Descarregar / Guardar no Telemóvel', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Guardar o ficheiro .xlsx no armazenamento'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final savePath = await FilePicker.platform.saveFile(
                    dialogTitle: 'Escolha onde guardar o Excel',
                    fileName: fileName,
                    type: FileType.custom,
                    allowedExtensions: ['xlsx'],
                    bytes: excelBytes,
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(savePath != null ? 'Excel guardado com sucesso!' : 'Ficheiro guardado em: ${tempFile.path}'),
                        backgroundColor: Colors.teal[800],
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.indigo),
                title: const Text('Partilhar Excel', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Enviar via WhatsApp, E-mail ou Drive'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Share.shareXFiles(
                    [XFile(tempFile.path)],
                    text: 'Mapa Excel CCTV - $driverName ($periodTitle)',
                  );
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar ficheiro Excel: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  // ==========================================
  // 3. TABELA DE VALORES DE REFERÊNCIA (PDF)
  // ==========================================
  static Future<Uint8List> _generateReferenceValuesBytes({
    required String driverName,
    required String driverNif,
    required String companyName,
    required String companyNif,
    required String driverType,
    required Map<String, double> rates,
    required Map<String, double> totals,
    required String nightStart,
    required String nightEnd,
    required String generationFormattedDate,
  }) async {
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontItalic = await PdfGoogleFonts.robotoItalic();

    final logo = await _loadLogoProvider();

    final pdf = pw.Document(
      title: 'Tabela de Valores de Referencia CCTV - $driverName',
      author: 'Rui Barata - CCTV Motorista',
      creator: 'CCTV Motorista App (BTE 29/2022)',
      subject: 'Tabela de Enquadramento Salarial e Parâmetros CCTV ANTROP',
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold, italic: fontItalic),
    );

    final base = rates['baseSalary'] ?? 942.00;
    final vhNorm = rates['vhNormal'] ?? ((base * 12) / (40 * 52));
    final vhRest = rates['vhRest'] ?? ((base / 30) / 8);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    if (logo != null)
                      pw.Container(width: 42, height: 42, margin: const pw.EdgeInsets.only(right: 8), child: pw.Image(logo)),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName.isNotEmpty ? companyName.toUpperCase() : 'CCTV MOTORISTA',
                          style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.blueGrey900),
                        ),
                        if (companyNif.isNotEmpty)
                          pw.Text('NIF Empresa: $companyNif', style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: PdfColors.grey700)),
                        pw.Text('Enquadramento: CCTV ANTROP (BTE 29/2022)', style: pw.TextStyle(font: fontRegular, fontSize: 8, color: PdfColors.blueGrey600)),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('TABELA DE VALORES DE REFERÊNCIA', style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: PdfColors.teal900)),
                    pw.Text('Regime: ${driverType == "Turismo" ? "Comercial / Turismo" : "Serviço Público"}', style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: PdfColors.blueGrey800)),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.blueGrey800),
            pw.SizedBox(height: 8),
            pw.Text('Identificação do Motorista e Regime:', style: pw.TextStyle(font: fontBold, fontSize: 10.5)),
            pw.SizedBox(height: 3),
            pw.Text('• Motorista: $driverName ${driverNif.isNotEmpty ? "(NIF: $driverNif)" : ""}'),
            pw.Text('• Regime Contratual: ${driverType == "Turismo" ? "Comercial / Turismo (Cobrança Diária)" : "Serviço Público (Cobrança Integrada no Base)"}'),
            pw.SizedBox(height: 14),
            pw.Text('Parâmetros Salariais e Fórmulas de Cálculo (BTE 29/2022):', style: pw.TextStyle(font: fontBold, fontSize: 10.5)),
            pw.SizedBox(height: 6),
            pw.Bullet(text: 'Vencimento Base Contratual: ${base.toStringAsFixed(2)} €'),
            if (driverType == 'Publico')
              pw.Bullet(text: 'Cláusula de Cobrança / Agente Único (20% embutido): ${(base - (base / 1.20)).toStringAsFixed(2)} € / mês')
            else
              pw.Bullet(text: 'Cláusula de Cobrança Diária (Turismo): ${(vhNorm * 8 * 0.20).toStringAsFixed(2)} € / dia assinalado (20% sobre 8h)'),
            pw.Bullet(text: 'Valor Hora Normal (VH): ${vhNorm.toStringAsFixed(2)} € / hora  [Fórmula: (Base × 12) / (40 × 52)]'),
            pw.Bullet(text: '1.ª Hora Extra em Dia Útil (50%): ${(vhNorm * 1.50).toStringAsFixed(2)} € / hora'),
            pw.Bullet(text: 'Horas Extras Seguintes em Dia Útil (75%): ${(vhNorm * 1.75).toStringAsFixed(2)} € / hora'),
            pw.Bullet(text: 'Trabalho em Folga/Feriado até 8h (200%): ${(vhRest * 2.00).toStringAsFixed(2)} € / hora (mínimo garantido: ${(vhRest * 2.00 * 5).toStringAsFixed(2)} € correspondente a 5h)'),
            pw.Bullet(text: 'Trabalho em Folga/Feriado após 8h (300%): ${(vhRest * 3.00).toStringAsFixed(2)} € / hora'),
            pw.Bullet(text: 'Acréscimo de Horário Noturno (+25%): +${(vhNorm * 0.25).toStringAsFixed(2)} € / hora (Período: $nightStart às $nightEnd)'),
            pw.Bullet(text: 'Subsídio de Alimentação Diário: ${(rates['mealAllowance'] ?? 5.50).toStringAsFixed(2)} € / dia'),
            pw.Bullet(text: '1.ª Refeição: Normal = ${(rates['firstMealNormal'] ?? 10.00).toStringAsFixed(2)} € | Penalizada = ${(rates['firstMealPenalized'] ?? 5.80).toStringAsFixed(2)} €'),
            pw.Bullet(text: '2.ª Refeição: Normal = ${(rates['secondMealNormal'] ?? 7.00).toStringAsFixed(2)} € | Penalizada = ${(rates['secondMealPenalized'] ?? 2.20).toStringAsFixed(2)} €'),
            pw.Spacer(),
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Documento não editável emitido pela aplicação CCTV Motorista',
                        style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.grey800)),
                    pw.Text('Desenvolvido por: Rui Barata © 2026 | Enquadramento BTE 29/2022',
                        style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: PdfColors.grey700)),
                    pw.Text('Gerado em: $generationFormattedDate',
                        style: pw.TextStyle(font: fontItalic, fontSize: 6.8, color: PdfColors.grey600)),
                  ],
                ),
                pw.Text('Declaração: Parâmetros calculados conforme CCTV ANTROP',
                    style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: PdfColors.grey600)),
              ],
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  static Future<void> exportReferenceValuesPDF({
    required BuildContext context,
    required String driverName,
    required String driverNif,
    required String companyName,
    required String companyNif,
    required String driverType,
    required Map<String, double> rates,
    required Map<String, double> totals,
    required String nightStart,
    required String nightEnd,
  }) async {
    final now = DateTime.now();
    final timestampForFileName = DateFormat('yyyyMMdd_HHmmss').format(now);
    final generationFormattedDate = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);

    final cleanDriver = driverName.trim().isEmpty ? 'Geral' : driverName.trim().replaceAll(' ', '_');
    final fileName = 'Tabela_Valores_Referencia_CCTV_${cleanDriver}_$timestampForFileName.pdf';

    final pdfBytes = await _generateReferenceValuesBytes(
      driverName: driverName,
      driverNif: driverNif,
      companyName: companyName,
      companyNif: companyNif,
      driverType: driverType,
      rates: rates,
      totals: totals,
      nightStart: nightStart,
      nightEnd: nightEnd,
      generationFormattedDate: generationFormattedDate,
    );

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blueGrey),
              title: const Text('Visualizar e Imprimir Tabela', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Pré-visualização e impressão direta'),
              onTap: () async {
                Navigator.pop(ctx);
                await Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: fileName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline, color: Colors.teal),
              title: const Text('Descarregar / Guardar no Telemóvel', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Guardar o ficheiro PDF no armazenamento'),
              onTap: () async {
                Navigator.pop(ctx);
                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/$fileName');
                await file.writeAsBytes(pdfBytes);

                final savePath = await FilePicker.platform.saveFile(
                  dialogTitle: 'Escolha onde guardar o PDF',
                  fileName: fileName,
                  type: FileType.custom,
                  allowedExtensions: ['pdf'],
                  bytes: pdfBytes,
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(savePath != null ? 'Tabela guardada com sucesso!' : 'Ficheiro guardado em: ${file.path}'),
                      backgroundColor: Colors.teal[800],
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.indigo),
              title: const Text('Partilhar PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Enviar via WhatsApp, E-mail ou Drive'),
              onTap: () async {
                Navigator.pop(ctx);
                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/$fileName');
                await file.writeAsBytes(pdfBytes);

                await Share.shareXFiles([XFile(file.path)], text: 'Tabela de Valores de Referência CCTV ANTROP - $driverName');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 4. MAPA DE CONTROLO DE VIATURAS (PDF)
  // ==========================================
  static Future<Uint8List> _generateVehiclePdfBytes({
    required String periodTitle,
    required String driverName,
    required String driverNif,
    required String companyName,
    required String companyNif,
    required List<DriverEntry> entryList,
    required String generationFormattedDate,
  }) async {
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontItalic = await PdfGoogleFonts.robotoItalic();

    final pdf = pw.Document(
      title: 'Mapa de Viaturas - $periodTitle - $driverName',
      author: 'Rui Barata - CCTV Motorista',
      creator: 'CCTV Motorista App (BTE 29/2022)',
      subject: 'Registo e Controlo de Viaturas e Escalas de Serviço',
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold, italic: fontItalic),
    );
    final logo = await _loadLogoProvider();

    List<List<String>> tableData = [];
    for (var e in entryList) {
      if (e.vehicleNumber.isNotEmpty || e.dayType == 'Util' || e.dayType == 'Descanso' || e.dayType == 'Feriado') {
        tableData.add([
          e.date,
          e.vehicleNumber.isNotEmpty ? e.vehicleNumber : '-',
          e.dayType,
          e.startTime.isNotEmpty ? e.startTime : '-',
          e.endTime.isNotEmpty ? e.endTime : '-',
          formatDuration(e.regularHours + e.overtimeHours),
          formatDuration(e.intermitenciaHours),
        ]);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        build: (context) => [
          // Cabeçalho Institucional
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  if (logo != null)
                    pw.Container(width: 40, height: 40, margin: const pw.EdgeInsets.only(right: 8), child: pw.Image(logo)),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        companyName.toUpperCase(),
                        style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.blueGrey900),
                      ),
                      if (companyNif.isNotEmpty)
                        pw.Text('NIF Empresa: $companyNif', style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: PdfColors.grey700)),
                      pw.Text('Enquadramento: CCTV ANTROP (BTE 29/2022)', style: pw.TextStyle(font: fontRegular, fontSize: 8, color: PdfColors.blueGrey600)),
                    ],
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('MAPA DE CONTROLO DE VIATURAS', style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: PdfColors.teal900)),
                  pw.Text('Mês / Período: $periodTitle', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.blueGrey800)),
                  pw.Text('Motorista: $driverName ${driverNif.isNotEmpty ? "(NIF: $driverNif)" : ""}', style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 0.8, color: PdfColors.teal800),
          pw.SizedBox(height: 8),

          // Tabela de Dados
          pw.Table.fromTextArray(
            headers: ['Data', 'Viatura / Frota', 'Tipo Serviço', 'Início', 'Fim', 'Trabalho Efetivo', 'Intermitência'],
            data: tableData,
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            headerStyle: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E293B)),
            cellStyle: pw.TextStyle(font: fontRegular, fontSize: 8),
            cellAlignment: pw.Alignment.center,
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC)),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
          ),
          pw.SizedBox(height: 14),

          // Rodapé com autoria, carimbo e assinatura
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Declaração: Os dados constantes deste documento são da exclusiva responsabilidade do utilizador.',
                      style: pw.TextStyle(font: fontBold, fontSize: 6.8, color: PdfColors.red900)),
                  pw.Text('Documento não editável emitido pela aplicação CCTV Motorista',
                      style: pw.TextStyle(font: fontRegular, fontSize: 6.6, color: PdfColors.grey800)),
                  pw.Text('Desenvolvido por: Rui Barata © 2026 | Enquadramento BTE 29/2022',
                      style: pw.TextStyle(font: fontRegular, fontSize: 6.4, color: PdfColors.grey700)),
                  pw.Text('Gerado em: $generationFormattedDate',
                        style: pw.TextStyle(font: fontItalic, fontSize: 6.4, color: PdfColors.grey600)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 200,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text('Assinatura do Motorista: $driverName', style: pw.TextStyle(font: fontBold, fontSize: 7.5)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> previewAndExportVehiclePDF({
    required BuildContext context,
    required String periodTitle,
    required String driverName,
    required String driverNif,
    required String companyName,
    required String companyNif,
    required List<DriverEntry> entryList,
  }) async {
    if (driverName.trim().isEmpty || companyName.trim().isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Dados Obrigatórios'),
            ],
          ),
          content: Text(
            driverName.trim().isEmpty
                ? 'É obrigatório definir o Nome do Motorista antes de gerar o Mapa de Viaturas.'
                : 'É obrigatório definir o Nome da Empresa antes de gerar o Mapa de Viaturas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final now = DateTime.now();
      final timestampForFileName = DateFormat('yyyyMMdd_HHmmss').format(now);
      final generationFormattedDate = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);

      final cleanDriver = driverName.trim().replaceAll(' ', '_');
      final cleanPeriod = periodTitle.replaceAll('/', '_');
      final fileName = 'Mapa_Viaturas_${cleanDriver}_${cleanPeriod}_$timestampForFileName.pdf';

      final pdfBytes = await _generateVehiclePdfBytes(
        periodTitle: periodTitle,
        driverName: driverName,
        driverNif: driverNif,
        companyName: companyName,
        companyNif: companyNif,
        entryList: entryList,
        generationFormattedDate: generationFormattedDate,
      );

      if (!context.mounted) return;

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.visibility, color: Colors.blueGrey),
                title: const Text('Visualizar e Imprimir Mapa de Viaturas', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Pré-visualização e impressão direta'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: fileName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_for_offline, color: Colors.teal),
                title: const Text('Descarregar / Guardar no Telemóvel', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Guardar o ficheiro PDF no armazenamento'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final tempDir = await getTemporaryDirectory();
                  final file = File('${tempDir.path}/$fileName');
                  await file.writeAsBytes(pdfBytes);

                  final savePath = await FilePicker.platform.saveFile(
                    dialogTitle: 'Escolha onde guardar o Mapa de Viaturas',
                    fileName: fileName,
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                    bytes: pdfBytes,
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(savePath != null ? 'Mapa de Viaturas guardado com sucesso!' : 'Ficheiro guardado em: ${file.path}'),
                        backgroundColor: Colors.teal[800],
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.indigo),
                title: const Text('Partilhar Mapa de Viaturas (PDF)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Enviar via WhatsApp, E-mail ou Drive'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final tempDir = await getTemporaryDirectory();
                  final file = File('${tempDir.path}/$fileName');
                  await file.writeAsBytes(pdfBytes);

                  await Share.shareXFiles(
                    [XFile(file.path)],
                    text: 'Mapa de Controlo de Viaturas - $driverName ($periodTitle)',
                  );
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar Mapa de Viaturas: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  // ==========================================
  // 5. MAPA ANUAL DE FÉRIAS (PDF) - CÉLULAS AMPLIADAS E VISÍVEIS
  // ==========================================
  static Future<Uint8List> _generateVacationsCalendarBytes({
    required int year,
    required String driverName,
    required String driverNif,
    required String companyName,
    required String companyNif,
    required List<DriverEntry> yearData,
    required String generationFormattedDate,
  }) async {
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontMedium = await PdfGoogleFonts.robotoMedium();
    final fontItalic = await PdfGoogleFonts.robotoItalic();

    final logo = await _loadLogoProvider();
    final vacationDates = yearData.where((e) => e.dayType == 'Ferias').map((e) => e.date).toSet();

    final pdf = pw.Document(
      title: 'Mapa Anual de Ferias $year - $driverName',
      author: 'Rui Barata - CCTV Motorista',
      creator: 'CCTV Motorista App (BTE 29/2022)',
      subject: 'Registo Anual de Férias do Motorista',
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold, italic: fontItalic),
    );

    const monthNames = [
      'JANEIRO', 'FEVEREIRO', 'MARÇO', 'ABRIL', 'MAIO', 'JUNHO',
      'JULHO', 'AGOSTO', 'SETEMBRO', 'OUTUBRO', 'NOVEMBRO', 'DEZEMBRO'
    ];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Cabeçalho
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logo != null)
                        pw.Container(
                          width: 38,
                          height: 38,
                          margin: const pw.EdgeInsets.only(right: 8),
                          child: pw.Image(logo),
                        ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'MAPA ANUAL DE CONTROLO DE FÉRIAS - $year',
                            style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.teal900),
                          ),
                          pw.Text(
                            companyName.isNotEmpty
                                ? 'Empresa: ${companyName.toUpperCase()} ${companyNif.isNotEmpty ? "(NIF: $companyNif)" : ""}'
                                : 'CCTV MOTORISTA',
                            style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: PdfColors.blueGrey800),
                          ),
                          pw.Text(
                            'Enquadramento: CCTV ANTROP (BTE 29/2022)',
                            style: pw.TextStyle(font: fontMedium, fontSize: 7.5, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Motorista: $driverName',
                          style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.blueGrey900)),
                      if (driverNif.isNotEmpty)
                        pw.Text('NIF: $driverNif', style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: PdfColors.grey700)),
                      pw.Container(
                        margin: const pw.EdgeInsets.only(top: 2),
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: const pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFF0F766E),
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                        child: pw.Text(
                          'Total Gozado: ${vacationDates.length} dias',
                          style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.8, color: PdfColors.teal800),
              pw.SizedBox(height: 4),

              // Grelha com Dias do Mês Ampliados (19x19 px com números a 9.5pt negrito)
              pw.Expanded(
                child: pw.GridView(
                  crossAxisCount: 4,
                  childAspectRatio: 1.25,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  children: List.generate(12, (mIdx) {
                    final month = mIdx + 1;
                    final monthTitle = monthNames[mIdx];
                    final daysInMonth = DateTime(year, month + 1, 0).day;

                    int monthVacCount = 0;
                    for (int d = 1; d <= daysInMonth; d++) {
                      final dStr = '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
                      if (vacationDates.contains(dStr)) monthVacCount++;
                    }

                    return pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.TableBorder.all(color: PdfColors.blueGrey300, width: 0.8),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        color: const PdfColor.fromInt(0xFFFAFAFA),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Container(
                            width: double.infinity,
                            padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 6),
                            decoration: const pw.BoxDecoration(
                              color: PdfColor.fromInt(0xFF1E293B),
                              borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(3)),
                            ),
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(monthTitle, style: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 8)),
                                if (monthVacCount > 0)
                                  pw.Text('$monthVacCount d',
                                      style: pw.TextStyle(font: fontBold, color: const PdfColor.fromInt(0xFF34D399), fontSize: 7.5))
                              ],
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Padding(
                              padding: const pw.EdgeInsets.all(3),
                              child: pw.Wrap(
                                spacing: 3,
                                runSpacing: 3,
                                alignment: pw.WrapAlignment.center,
                                children: List.generate(daysInMonth, (dIdx) {
                                  final day = dIdx + 1;
                                  final dStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                                  final isVacation = vacationDates.contains(dStr);

                                  return pw.Container(
                                    width: 19,
                                    height: 19,
                                    decoration: pw.BoxDecoration(
                                      color: isVacation ? const PdfColor.fromInt(0xFF0F766E) : const PdfColor.fromInt(0xFFE2E8F0),
                                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2.5)),
                                      border: isVacation ? pw.TableBorder.all(color: const PdfColor.fromInt(0xFF115E59), width: 0.8) : null,
                                    ),
                                    child: pw.Center(
                                      child: pw.Text(
                                        '$day',
                                        style: pw.TextStyle(
                                          font: isVacation ? fontBold : fontMedium,
                                          fontSize: 9.5,
                                          color: isVacation ? PdfColors.white : PdfColors.blueGrey900,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),

              // Rodapé
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Container(width: 9, height: 9, color: const PdfColor.fromInt(0xFF0F766E)),
                          pw.SizedBox(width: 4),
                          pw.Text('Verde = Dia de Férias Gozado', style: pw.TextStyle(font: fontBold, fontSize: 7.2, color: PdfColors.teal900)),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Declaração: Os dados constantes deste documento são da exclusiva responsabilidade do utilizador.',
                          style: pw.TextStyle(font: fontBold, fontSize: 6.8, color: PdfColors.red900)),
                      pw.Text('Documento não editável emitido pela aplicação CCTV Motorista',
                          style: pw.TextStyle(font: fontRegular, fontSize: 6.6, color: PdfColors.grey800)),
                      pw.Text('Criador: Rui Barata © 2026 | Enquadramento BTE 29/2022',
                          style: pw.TextStyle(font: fontRegular, fontSize: 6.4, color: PdfColors.grey700)),
                      pw.Text('Gerado em: $generationFormattedDate',
                          style: pw.TextStyle(font: fontItalic, fontSize: 6.4, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: 220,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text('Assinatura do Motorista: $driverName', style: pw.TextStyle(font: fontBold, fontSize: 7.5)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> exportVacationsCalendarPDF({
    required BuildContext context,
    required int year,
    required String driverName,
    required String driverNif,
    required String companyName,
    required String companyNif,
    required List<DriverEntry> yearData,
  }) async {
    if (driverName.trim().isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Nome Obrigatório'),
            ],
          ),
          content: const Text(
            'É obrigatório definir o Nome do Motorista antes de gerar o Mapa Anual de Férias em PDF.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final now = DateTime.now();
      final timestampForFileName = DateFormat('yyyyMMdd_HHmmss').format(now);
      final generationFormattedDate = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);

      final cleanDriver = driverName.trim().replaceAll(' ', '_');
      final fileName = 'Mapa_Anual_Ferias_${year}_${cleanDriver}_$timestampForFileName.pdf';

      final pdfBytes = await _generateVacationsCalendarBytes(
        year: year,
        driverName: driverName,
        driverNif: driverNif,
        companyName: companyName,
        companyNif: companyNif,
        yearData: yearData,
        generationFormattedDate: generationFormattedDate,
      );

      if (!context.mounted) return;

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.visibility, color: Colors.blueGrey),
                title: const Text('Visualizar e Imprimir Mapa de Férias', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Pré-visualização e impressão direta'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: fileName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_for_offline, color: Colors.teal),
                title: const Text('Descarregar / Guardar no Telemóvel', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Guardar o ficheiro PDF no armazenamento'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final tempDir = await getTemporaryDirectory();
                  final file = File('${tempDir.path}/$fileName');
                  await file.writeAsBytes(pdfBytes);

                  final savePath = await FilePicker.platform.saveFile(
                    dialogTitle: 'Escolha onde guardar o Mapa de Férias',
                    fileName: fileName,
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                    bytes: pdfBytes,
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(savePath != null ? 'Mapa de Férias guardado com sucesso!' : 'Ficheiro guardado em: ${file.path}'),
                        backgroundColor: Colors.teal[800],
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.indigo),
                title: const Text('Partilhar Mapa de Férias (PDF)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Enviar via WhatsApp, E-mail ou Drive'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final tempDir = await getTemporaryDirectory();
                  final file = File('${tempDir.path}/$fileName');
                  await file.writeAsBytes(pdfBytes);

                  await Share.shareXFiles(
                    [XFile(file.path)],
                    text: 'Mapa Anual de Férias $year - $driverName',
                  );
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar Mapa de Férias: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  // ==========================================
  // 6. BACKUP JSON LOCAL
  // ==========================================
  static Future<void> exportBackupJSON() async {
    final entries = await DBHelper.instance.getAllEntries();
    final data = jsonEncode(entries.map((e) => e.toMap()).toList());

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/CCTV_Motorista_Backup.json');
    await file.writeAsString(data);

    await Share.shareXFiles([XFile(file.path)], text: 'Cópia de Segurança Local CCTV Motorista');
  }

  static Future<bool> importBackupJSON() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);

      for (var item in jsonList) {
        final entry = DriverEntry.fromMap(item as Map<String, dynamic>);
        await DBHelper.instance.insertOrUpdate(entry);
      }
      return true;
    }
    return false;
  }
}