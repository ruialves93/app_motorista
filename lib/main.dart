import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/driver_entry.dart';
import 'screens/lock_screen.dart';
import 'services/auth_service.dart';
import 'services/cloud_service.dart';
import 'services/db_helper.dart';
import 'services/export_service.dart';
import 'services/update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: AppRoot(), debugShowCheckedModeBanner: false));
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _isLocked = true;
  bool _hasCheckedLock = false;

  @override
  void initState() {
    super.initState();
    _checkSecurity();
  }

  Future<void> _checkSecurity() async {
    final lockEnabled = await AuthService.isLockEnabled();
    setState(() {
      _isLocked = lockEnabled;
      _hasCheckedLock = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCheckedLock) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_isLocked) {
      return LockScreen(onUnlocked: () => setState(() => _isLocked = false));
    }
    return const DriverCCTVApp();
  }
}

class DriverCCTVApp extends StatefulWidget {
  const DriverCCTVApp({super.key});

  @override
  State<DriverCCTVApp> createState() => _DriverCCTVAppState();
}

class _DriverCCTVAppState extends State<DriverCCTVApp> {
  String driverName = '';
  String driverNif = '';
  String companyName = '';
  String companyNif = '';
  String accountEmail = '';
  String driverType = 'Publico';

  bool isAppLockEnabled = false;

  double baseSalary = 942.00;
  double mealAllowance = 5.50;
  double firstMealNormal = 10.00;
  double secondMealNormal = 7.00;
  double firstMealPenalized = 5.80;
  double secondMealPenalized = 2.20;
  String nightStart = '20:00';
  String nightEnd = '07:00';

  DateTime focusedMonth = DateTime.now();
  DateTime selectedDay = DateTime.now();
  Map<String, DriverEntry> entryMap = {};

  int annualVacationDays = 0;

  @override
  void initState() {
    super.initState();
    _loadGlobalPreferences();
    _loadMonthRatesAndEntries();
    CloudService.checkAndRunDailySync();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdates(context);
    });
  }

  String get _currentYmKey => DateFormat('yyyy_MM').format(focusedMonth);
  String get _periodTitle => DateFormat('MM/yyyy').format(focusedMonth);

  String _formatHours(double decimalHours) {
    if (decimalHours <= 0.001) return '00:00';
    int totalMinutes = (decimalHours * 60).round();
    int h = totalMinutes ~/ 60;
    int m = totalMinutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  void _triggerAutoCloudSync() {
    if (accountEmail.isNotEmpty) {
      CloudService.uploadOrReplaceBackupOnDrive();
    }
  }

  Future<void> _loadGlobalPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      driverName = prefs.getString('driver_name') ?? '';
      driverNif = prefs.getString('driver_nif') ?? '';
      companyName = prefs.getString('company_name') ?? '';
      companyNif = prefs.getString('company_nif') ?? '';
      accountEmail = prefs.getString('google_account_email') ?? '';
      isAppLockEnabled = prefs.getBool('app_lock_enabled') ?? false;
      driverType = prefs.getString('driver_type') ?? 'Publico';
    });
  }

  Future<void> _loadMonthRatesAndEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final ym = _currentYmKey;

    final b = prefs.getDouble('base_salary_$ym') ?? prefs.getDouble('base_salary') ?? 942.00;
    final m = prefs.getDouble('meal_allowance_$ym') ?? prefs.getDouble('meal_allowance') ?? 5.50;
    final m1n = prefs.getDouble('first_meal_normal_$ym') ?? prefs.getDouble('first_meal_normal') ?? 10.00;
    final m2n = prefs.getDouble('second_meal_normal_$ym') ?? prefs.getDouble('second_meal_normal') ?? 7.00;
    final m1p = prefs.getDouble('first_meal_penalized_$ym') ?? prefs.getDouble('first_meal_penalized') ?? 5.80;
    final m2p = prefs.getDouble('second_meal_penalized_$ym') ?? prefs.getDouble('second_meal_penalized') ?? 2.20;
    final ns = prefs.getString('night_start_$ym') ?? prefs.getString('night_start') ?? '20:00';
    final ne = prefs.getString('night_end_$ym') ?? prefs.getString('night_end') ?? '07:00';
    final dt = prefs.getString('driver_type_$ym') ?? prefs.getString('driver_type') ?? 'Publico';

    final ymDate = DateFormat('yyyy-MM').format(focusedMonth);
    final data = await DBHelper.instance.getEntriesBetween('$ymDate-01', '$ymDate-31');

    final yearStr = DateFormat('yyyy').format(focusedMonth);
    final yearData = await DBHelper.instance.getEntriesBetween('$yearStr-01-01', '$yearStr-12-31');
    final countVacations = yearData.where((e) => e.dayType == 'Ferias').length;

    setState(() {
      baseSalary = b;
      mealAllowance = m;
      firstMealNormal = m1n;
      secondMealNormal = m2n;
      firstMealPenalized = m1p;
      secondMealPenalized = m2p;
      nightStart = ns;
      nightEnd = ne;
      driverType = dt;

      entryMap = {for (var e in data) e.date: e};
      annualVacationDays = countVacations;
    });
  }

  Map<String, double> _getRatesMap() {
    return {
      'baseSalary': baseSalary,
      'vhNormal': (baseSalary * 12) / (40 * 52),
      'vhRest': (baseSalary / 30) / 8,
      'mealAllowance': mealAllowance,
      'firstMealNormal': firstMealNormal,
      'secondMealNormal': secondMealNormal,
      'firstMealPenalized': firstMealPenalized,
      'secondMealPenalized': secondMealPenalized,
    };
  }

  Map<String, double> _calculateCCTVTotals() {
    final rates = _getRatesMap();
    final vhNormal = rates['vhNormal']!;
    final vhRest = rates['vhRest']!;
    final dailyDeduction = baseSalary / 30;

    double totalOvertimePay = 0;
    double totalRestWorkPay = 0;
    double totalNightPay = 0;
    double totalMealsPay = 0;
    double totalDeductions = 0;
    double totalDailyCollectionPay = 0;
    int folgasCount = 0;
    int monthVacationsCount = 0;

    final includedCollection = driverType == 'Publico' ? (baseSalary - (baseSalary / 1.20)) : 0.0;

    for (var e in entryMap.values) {
      if (e.dayType == 'Folga') folgasCount++;
      if (e.dayType == 'Ferias') monthVacationsCount++;

      if (e.dayType == 'Baixa' || e.dayType == 'Falta') {
        totalDeductions += dailyDeduction;
      }

      if (e.dayType == 'Util') {
        double ot = e.overtimeHours;
        if (ot > 0) {
          double firstHour = ot >= 1.0 ? 1.0 : ot;
          double remaining = ot > 1.0 ? ot - 1.0 : 0.0;
          totalOvertimePay += (firstHour * vhNormal * 1.50) + (remaining * vhNormal * 1.75);
        }
      }

      if (e.dayType == 'Descanso' || e.dayType == 'Feriado') {
        double hours = e.regularHours + e.overtimeHours;
        if (hours > 0) {
          double paid200 = hours < 5.0 ? 5.0 : (hours > 8.0 ? 8.0 : hours);
          double paid300 = hours > 8.0 ? hours - 8.0 : 0.0;
          totalRestWorkPay += (paid200 * vhRest * 2.00) + (paid300 * vhRest * 3.00);
        }
      }

      if (e.nightHours > 0) {
        totalNightPay += e.nightHours * (vhNormal * 0.25);
      }

      if (driverType == 'Turismo' && e.hasCollection && (e.dayType == 'Util' || e.dayType == 'Descanso' || e.dayType == 'Feriado')) {
        totalDailyCollectionPay += vhNormal * 8.0 * 0.20;
      }

      if (e.dayType != 'Baixa' && e.dayType != 'Falta' && e.dayType != 'Folga' && e.dayType != 'Ferias') {
        if (e.hasMealAllowance) {
          totalMealsPay += mealAllowance;
        } else {
          if (e.firstMeal == 'Normal') totalMealsPay += firstMealNormal;
          if (e.firstMeal == 'Penalizada') totalMealsPay += firstMealPenalized;
          if (e.secondMeal == 'Normal') totalMealsPay += secondMealNormal;
          if (e.secondMeal == 'Penalizada') totalMealsPay += secondMealPenalized;
        }
      }
    }

    double grossEarnings = (baseSalary - totalDeductions) +
        totalDailyCollectionPay +
        totalOvertimePay +
        totalRestWorkPay +
        totalNightPay +
        totalMealsPay;

    return {
      'baseSalary': baseSalary,
      'gross': grossEarnings,
      'deductions': totalDeductions,
      'includedCollection': includedCollection,
      'dailyCollection': totalDailyCollectionPay,
      'overtime': totalOvertimePay,
      'restWork': totalRestWorkPay,
      'night': totalNightPay,
      'meals': totalMealsPay,
      'restDaysCount': folgasCount.toDouble(),
      'vacationsMonthCount': monthVacationsCount.toDouble(),
    };
  }

  double _calculateNightHours(String startStr, String endStr) {
    if (!startStr.contains(':') || !endStr.contains(':')) return 0.0;

    int toMin(String s) {
      final p = s.split(':');
      return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
    }

    int startM = toMin(startStr);
    int endM = toMin(endStr);
    if (endM < startM) endM += 1440;

    int nStartM = toMin(nightStart);
    int nEndM = toMin(nightEnd);

    int nightMinutes = 0;

    for (int m = startM; m < endM; m++) {
      int curMinOfDay = m % 1440;
      bool isNight = false;

      if (nStartM > nEndM) {
        if (curMinOfDay >= nStartM || curMinOfDay < nEndM) {
          isNight = true;
        }
      } else {
        if (curMinOfDay >= nStartM && curMinOfDay < nEndM) {
          isNight = true;
        }
      }

      if (isNight) nightMinutes++;
    }

    return nightMinutes / 60.0;
  }

  @override
  Widget build(BuildContext context) {
    final totals = _calculateCCTVTotals();
    final rates = _getRatesMap();
    final selectedDateStr = DateFormat('yyyy-MM-dd').format(selectedDay);
    final selectedEntry = entryMap[selectedDateStr];

    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white, size: 28),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 3,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/logo_rb.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.directions_bus, size: 22, color: Color(0xFF1E293B)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    companyName.isEmpty ? 'CCTV Motorista' : companyName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.3),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Mês: $_periodTitle • ${driverType == "Turismo" ? "Turismo" : "Serv. Público"}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFFE2E8F0)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      drawer: _buildDrawer(rates, totals),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildSummaryCard(totals),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: TableCalendar(
                firstDay: DateTime(2022),
                lastDay: DateTime(2035),
                focusedDay: focusedMonth,
                currentDay: DateTime.now(),
                calendarFormat: CalendarFormat.month,
                headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
                selectedDayPredicate: (day) => isSameDay(selectedDay, day),
                onDaySelected: (sDay, fDay) {
                  setState(() {
                    selectedDay = sDay;
                    focusedMonth = fDay;
                  });
                },
                onPageChanged: (fDay) {
                  setState(() => focusedMonth = fDay);
                  _loadMonthRatesAndEntries();
                },
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) => _buildCalendarCell(day),
                  selectedBuilder: (context, day, focusedDay) => _buildCalendarCell(day, isSelected: true),
                  todayBuilder: (context, day, focusedDay) => _buildCalendarCell(day, isToday: true),
                ),
              ),
            ),
            _buildSelectedDayDetail(selectedDateStr, selectedEntry),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.blueGrey[50],
              child: const Center(
                child: Text('Desenvolvido por Rui Barata © 2026', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCell(DateTime day, {bool isSelected = false, bool isToday = false}) {
    final dStr = DateFormat('yyyy-MM-dd').format(day);
    final entry = entryMap[dStr];

    Color? bg;
    if (entry != null) {
      bg = _getDayColor(entry.dayType);
    }

    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bg ?? (isSelected ? Colors.blueGrey[100] : Colors.transparent),
        shape: BoxShape.circle,
        border: isSelected ? Border.all(color: Colors.blueGrey[900]!, width: 2) : (isToday ? Border.all(color: Colors.blueAccent, width: 1.5) : null),
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: TextStyle(
            color: entry != null ? Colors.white : Colors.black87,
            fontWeight: (isSelected || isToday || entry != null) ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedDayDetail(String dStr, DriverEntry? entry) {
    return Card(
      margin: const EdgeInsets.all(10),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text('Dia: $dStr', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                if (entry != null)
                  Chip(
                    label: Text(
                      entry.dayType == 'Folga'
                          ? 'FOLGA'
                          : (entry.dayType == 'Ferias'
                              ? 'FÉRIAS'
                              : (entry.dayType == 'Descanso' ? 'DESCANSO (Trab.)' : entry.dayType)),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    backgroundColor: _getDayColor(entry.dayType),
                  )
                else
                  const Text('Sem Registo', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const Divider(),
            if (entry != null) ...[
              if (entry.dayType == 'Folga')
                const Text('Motorista de Folga (Dia de Descanso Gozado)', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13))
              else if (entry.dayType == 'Ferias')
                const Text('Motorista em Período de Férias', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 13))
              else ...[
                Text('Horário: ${entry.startTime.isNotEmpty ? entry.startTime : "-"} às ${entry.endTime.isNotEmpty ? entry.endTime : "-"} | Viatura: ${entry.vehicleNumber.isNotEmpty ? entry.vehicleNumber : "-"}'),
                Text('Trabalho: ${_formatHours(entry.regularHours + entry.overtimeHours)} (Norm: ${_formatHours(entry.regularHours)} | Ext: ${_formatHours(entry.overtimeHours)}) | Interm.: ${_formatHours(entry.intermitenciaHours)}'),
                if (entry.hasCollection && driverType == 'Turismo')
                  const Text('• Serviço com Cobrança de Bilhetes (+20% 8h)', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 12)),
                if (entry.nightHours > 0)
                  Text('Horas Noturnas: ${_formatHours(entry.nightHours)} (Período: $nightStart às $nightEnd)', style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ] else
              const Text('Nenhum serviço ou folga registada para este dia.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.edit, size: 16),
                    label: Text(entry == null ? 'Registar Serviço' : 'Editar Serviço'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[900], foregroundColor: Colors.white),
                    onPressed: () => _openEntryEditor(entry, dStr),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.beach_access, size: 16, color: Colors.blue),
                  label: const Text('Folga'),
                  onPressed: () async {
                    final folgaEntry = DriverEntry(
                      id: entry?.id,
                      date: dStr,
                      dayType: 'Folga',
                      regularHours: 0.0,
                      overtimeHours: 0.0,
                      intermitenciaHours: 0.0,
                      nightHours: 0.0,
                      hasMealAllowance: false,
                    );
                    await DBHelper.instance.insertOrUpdate(folgaEntry);
                    _triggerAutoCloudSync();
                    _loadMonthRatesAndEntries();
                  },
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.flight_takeoff, size: 16, color: Colors.teal),
                  label: const Text('Férias'),
                  onPressed: () async {
                    final feriasEntry = DriverEntry(
                      id: entry?.id,
                      date: dStr,
                      dayType: 'Ferias',
                      regularHours: 0.0,
                      overtimeHours: 0.0,
                      intermitenciaHours: 0.0,
                      nightHours: 0.0,
                      hasMealAllowance: false,
                    );
                    await DBHelper.instance.insertOrUpdate(feriasEntry);
                    _triggerAutoCloudSync();
                    _loadMonthRatesAndEntries();
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Color _getDayColor(String dayType) {
    switch (dayType) {
      case 'Util': return Colors.green;
      case 'Folga': return Colors.blue;
      case 'Ferias': return Colors.teal;
      case 'Descanso': return Colors.indigo;
      case 'Feriado': return Colors.purple;
      case 'Baixa': return Colors.orange;
      case 'Falta': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildSummaryCard(Map<String, double> t) {
    return Card(
      margin: const EdgeInsets.all(10),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Bruto Estimado:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('Mês de $_periodTitle (${driverType == "Turismo" ? "Comercial / Turismo" : "Serviço Público"})', style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
                  ],
                ),
                Text('${t['gross']!.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('Base: ${baseSalary.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 11.5)),
                if (driverType == 'Publico')
                  Text('Cobrança Incluída (20%): ${t['includedCollection']!.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 11.5, color: Colors.indigo, fontWeight: FontWeight.w600))
                else if ((t['dailyCollection'] ?? 0) > 0)
                  Text('Cobrança Diária: +${t['dailyCollection']!.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 11.5, color: Colors.indigo, fontWeight: FontWeight.w600)),
                Text('Folgas: ${t['restDaysCount']!.toInt()} dias', style: const TextStyle(fontSize: 11.5, color: Colors.blue, fontWeight: FontWeight.w600)),
                Text('Férias Mês: ${t['vacationsMonthCount']!.toInt()} dias', style: const TextStyle(fontSize: 11.5, color: Colors.teal, fontWeight: FontWeight.w600)),
                Text('Horas 50%/75%: +${t['overtime']!.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 11.5)),
                Text('Desc./Fer. (200%/300%): +${t['restWork']!.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 11.5)),
                Text('Noturno: +${t['night']!.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 11.5)),
                Text('Refeições: +${t['meals']!.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 11.5)),
                if (t['deductions']! > 0)
                  Text('Descontos: -${t['deductions']!.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 11.5, color: Colors.red)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(Map<String, double> rates, Map<String, double> totals) {
    final entryList = entryMap.values.toList()..sort((a, b) => a.date.compareTo(b.date));

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF1E293B)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/logo_rb.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.directions_bus, size: 30, color: Color(0xFF1E293B)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(driverName.isNotEmpty ? driverName : 'CCTV Motorista', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                Text(
                  '${driverType == "Turismo" ? "Comercial / Turismo" : "Serviço Público"} ${accountEmail.isNotEmpty ? "• $accountEmail" : ""}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.blueGrey),
            title: const Text('Dados do Motorista'),
            subtitle: Text(driverName.isEmpty ? 'Definir Nome e NIF' : '$driverName ${driverNif.isNotEmpty ? "(NIF: $driverNif)" : ""}'),
            onTap: () {
              Navigator.pop(context);
              _openDriverDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.business, color: Colors.blueGrey),
            title: const Text('Dados da Empresa'),
            subtitle: Text(companyName.isEmpty ? 'Definir Nome e NIF' : '$companyName ${companyNif.isNotEmpty ? "(NIF: $companyNif)" : ""}'),
            onTap: () {
              Navigator.pop(context);
              _openCompanyDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.indigo),
            title: Text('Definições Salariais ($_periodTitle)'),
            subtitle: Text('${driverType == "Turismo" ? "Turismo" : "Serv. Público"} | Base: ${baseSalary.toStringAsFixed(2)} €'),
            onTap: () {
              Navigator.pop(context);
              _openSettingsDialog();
            },
          ),
          ListTile(
            leading: Icon(isAppLockEnabled ? Icons.lock : Icons.lock_open, color: isAppLockEnabled ? Colors.green : Colors.blueGrey),
            title: const Text('Segurança e Bloqueio'),
            subtitle: Text(isAppLockEnabled ? 'PIN e Biometria Ativos' : 'Bloqueio Desativado'),
            onTap: () {
              Navigator.pop(context);
              _openSecurityDialog();
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 4, bottom: 4),
            child: Text('CÓPIA & SINCRONIZAÇÃO EM NUVEM', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ListTile(
            leading: Icon(Icons.cloud_sync, color: accountEmail.isNotEmpty ? Colors.teal : Colors.blueGrey),
            title: const Text('Google Drive (Backup Automático)'),
            subtitle: Text(accountEmail.isEmpty ? 'Toque para ligar conta Google' : 'Ligado: $accountEmail (Auto-Sync Ativo)'),
            onTap: () {
              Navigator.pop(context);
              _openCloudDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload, color: Colors.teal),
            title: const Text('Exportar Backup Local'),
            subtitle: const Text('Guardar cópia .json no dispositivo'),
            onTap: () async {
              Navigator.pop(context);
              await ExportService.exportBackupJSON();
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download, color: Colors.orange),
            title: const Text('Importar Backup'),
            subtitle: const Text('Restaurar dados num novo equipamento'),
            onTap: () async {
              Navigator.pop(context);
              final ok = await ExportService.importBackupJSON();
              if (ok) {
                await _loadGlobalPreferences();
                await _loadMonthRatesAndEntries();
                _triggerAutoCloudSync();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados restaurados com sucesso!')));
                }
              }
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 4, bottom: 4),
            child: Text('EXPORTAÇÕES & RELATÓRIOS', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ListTile(
            leading: const Icon(Icons.flight_takeoff, color: Colors.teal),
            title: const Text('Mapa Anual de Férias (PDF)'),
            subtitle: Text('Calendário anual completo ($annualVacationDays dias gozados)'),
            onTap: () async {
              Navigator.pop(context);
              final year = focusedMonth.year;
              final yearData = await DBHelper.instance.getEntriesBetween('$year-01-01', '$year-12-31');
              ExportService.exportVacationsCalendarPDF(
                context: context,
                year: year,
                driverName: driverName,
                driverNif: driverNif,
                companyName: companyName,
                companyNif: companyNif,
                yearData: yearData,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.assessment, color: Colors.indigo),
            title: const Text('Exportar Valores de Referência'),
            subtitle: const Text('PDF com Vencimento, Descansos, etc.'),
            onTap: () {
              Navigator.pop(context);
              ExportService.exportReferenceValuesPDF(
                context: context,
                driverName: driverName,
                driverNif: driverNif,
                companyName: companyName,
                companyNif: companyNif,
                driverType: driverType,
                rates: rates,
                totals: totals,
                nightStart: nightStart,
                nightEnd: nightEnd,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
            title: const Text('Visualizar / Exportar PDF'),
            subtitle: const Text('Folha de Serviço e Vencimentos'),
            onTap: () {
              Navigator.pop(context);

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
                    content: const Text('É obrigatório definir o Nome do Motorista antes de gerar a Folha de Serviço em PDF para aposição da assinatura.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), foregroundColor: Colors.white),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openDriverDialog();
                        },
                        child: const Text('Preencher Nome'),
                      ),
                    ],
                  ),
                );
                return;
              }

              ExportService.previewAndExportPDF(
                context: context,
                periodTitle: _periodTitle,
                driverName: driverName,
                driverNif: driverNif,
                companyName: companyName,
                companyNif: companyNif,
                driverType: driverType,
                entryList: entryList,
                rates: rates,
                totals: totals,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.directions_bus, color: Colors.blueAccent),
            title: const Text('PDF Registo de Viaturas'),
            subtitle: const Text('Mapa de frota e horários'),
            onTap: () {
              Navigator.pop(context);
              ExportService.previewAndExportVehiclePDF(
                context: context,
                periodTitle: _periodTitle,
                driverName: driverName,
                driverNif: driverNif,
                companyName: companyName,
                companyNif: companyNif,
                entryList: entryList,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_view, color: Colors.green),
            title: const Text('Exportar Excel (.xlsx)'),
            subtitle: const Text('Tabela detalhada com fórmulas'),
            onTap: () {
              Navigator.pop(context);
              ExportService.previewAndExportExcel(
                context: context,
                periodTitle: _periodTitle,
                driverName: driverName,
                driverNif: driverNif,
                companyName: companyName,
                companyNif: companyNif,
                driverType: driverType,
                entryList: entryList,
                rates: rates,
                totals: totals,
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.system_update, color: Colors.teal),
            title: const Text('Procurar Atualizações'),
            subtitle: Text('Versão instalada: v${UpdateService.currentVersion}'),
            onTap: () {
              Navigator.pop(context);
              UpdateService.checkForUpdates(context, showNoUpdateMessage: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book, color: Colors.indigo),
            title: const Text('Consultar BTE 29/2022'),
            subtitle: const Text('CCTV ANTROP em PDF Oficial'),
            onTap: () async {
              Navigator.pop(context);
              final uri = Uri.parse('https://bte.dgcp.mtsss.gov.pt/completos/2022/bte29_2022.pdf');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.email, color: Colors.deepOrange),
            title: const Text('Contactar Programador'),
            subtitle: const Text('Abrir Gmail para envio direto'),
            onTap: () async {
              Navigator.pop(context);
              final ok = await CloudService.openGmailContact(driverName: driverName, driverNif: driverNif, companyName: companyName);
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir a aplicação de e-mail.')));
              }
            },
          ),
          const Divider(),
          // Bloco do Programador no Final do Menu
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            color: const Color(0xFFF1F5F9),
            child: const Column(
              children: [
                Text(
                  'Desenvolvido por Rui Barata © 2026',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'CCTV ANTROP (BTE 29/2022)',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.blueGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openCloudDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google Drive & Backup Automático'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (accountEmail.isNotEmpty) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                title: const Text('Sessão Google Conectada', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(accountEmail),
              ),
              const SizedBox(height: 8),
              const Text(
                '• A sincronização em tempo real está ativa.\n• Todas as gravações são salvas automaticamente na sua nuvem Google Drive.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar Manualmente Agora'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[900], foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final ok = await CloudService.uploadOrReplaceBackupOnDrive();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? 'Backup sincronizado no Google Drive!' : 'Erro na sincronização.'),
                        backgroundColor: ok ? Colors.green[800] : Colors.red[800],
                      ),
                    );
                  }
                },
              ),
            ] else ...[
              const Text(
                'Ligue a sua conta Google para ativar a sincronização automática em tempo real e nunca perder os seus registos.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.account_circle),
                label: const Text('Ligar Conta Google Drive'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[900], foregroundColor: Colors.white),
                onPressed: () async {
                  final acc = await CloudService.signInGoogle();
                  if (acc != null) {
                    setState(() => accountEmail = acc.email);
                    await _loadGlobalPreferences();
                    await _loadMonthRatesAndEntries();
                    if (ctx.mounted) Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Conectado a ${acc.email}. Dados sincronizados!'),
                        backgroundColor: Colors.green[800],
                      ),
                    );
                  }
                },
              ),
            ],
          ],
        ),
        actions: [
          if (accountEmail.isNotEmpty)
            TextButton(
              child: const Text('Terminar Sessão', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                await CloudService.signOut();
                setState(() => accountEmail = '');
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          TextButton(child: const Text('Fechar'), onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  void _openDriverDialog() {
    final nameCtrl = TextEditingController(text: driverName);
    final nifCtrl = TextEditingController(text: driverNif);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dados do Motorista'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nome do Motorista')),
            TextField(controller: nifCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'NIF do Motorista')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            child: const Text('Guardar'),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('driver_name', nameCtrl.text.trim());
              await prefs.setString('driver_nif', nifCtrl.text.trim());
              setState(() {
                driverName = nameCtrl.text.trim();
                driverNif = nifCtrl.text.trim();
              });
              _triggerAutoCloudSync();
              if (ctx.mounted) Navigator.pop(ctx);
            },
          )
        ],
      ),
    );
  }

  void _openCompanyDialog() {
    final compCtrl = TextEditingController(text: companyName);
    final nifCtrl = TextEditingController(text: companyNif);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dados da Empresa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: compCtrl, decoration: const InputDecoration(labelText: 'Nome da Empresa')),
            TextField(controller: nifCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'NIF da Empresa')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            child: const Text('Guardar'),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('company_name', compCtrl.text.trim());
              await prefs.setString('company_nif', nifCtrl.text.trim());
              setState(() {
                companyName = compCtrl.text.trim();
                companyNif = nifCtrl.text.trim();
              });
              _triggerAutoCloudSync();
              if (ctx.mounted) Navigator.pop(ctx);
            },
          )
        ],
      ),
    );
  }

  void _openSecurityDialog() {
    bool enableLock = isAppLockEnabled;
    final pinCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text('Bloqueio e Segurança'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Ativar Bloqueio de Acesso'),
                value: enableLock,
                onChanged: (val) => setDState(() => enableLock = val),
              ),
              if (enableLock)
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'Definir PIN (4 a 6 dígitos)'),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              child: const Text('Guardar'),
              onPressed: () async {
                await AuthService.setLock(enableLock, pinCtrl.text.isNotEmpty ? pinCtrl.text : null);
                setState(() => isAppLockEnabled = enableLock);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            )
          ],
        ),
      ),
    );
  }

  void _openSettingsDialog() {
    final baseCtrl = TextEditingController(text: baseSalary.toStringAsFixed(2));
    final mealCtrl = TextEditingController(text: mealAllowance.toStringAsFixed(2));
    final m1NormCtrl = TextEditingController(text: firstMealNormal.toStringAsFixed(2));
    final m2NormCtrl = TextEditingController(text: secondMealNormal.toStringAsFixed(2));
    final m1PenCtrl = TextEditingController(text: firstMealPenalized.toStringAsFixed(2));
    final m2PenCtrl = TextEditingController(text: secondMealPenalized.toStringAsFixed(2));
    final nStartCtrl = TextEditingController(text: nightStart);
    final nEndCtrl = TextEditingController(text: nightEnd);

    String selectedType = driverType;
    bool applyToFutureMonths = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          Future<void> pickNightTime(TextEditingController ctrl) async {
            TimeOfDay initial = const TimeOfDay(hour: 20, minute: 0);
            if (ctrl.text.contains(':')) {
              final parts = ctrl.text.split(':');
              initial = TimeOfDay(hour: int.tryParse(parts[0]) ?? 20, minute: int.tryParse(parts[1]) ?? 0);
            }
            final picked = await showTimePicker(context: context, initialTime: initial);
            if (picked != null) {
              setDState(() {
                ctrl.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
              });
            }
          }

          return AlertDialog(
            title: Text('Definições Salariais - Mês $_periodTitle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tipo / Regime de Motorista:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    items: const [
                      DropdownMenuItem(value: 'Publico', child: Text('Serviço Público (Cobrança 20% no Salário)')),
                      DropdownMenuItem(value: 'Turismo', child: Text('Comercial / Turismo (Cobrança Diária 8h)')),
                    ],
                    onChanged: (val) => setDState(() => selectedType = val!),
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: baseCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Vencimento Base (€)')),
                  TextField(controller: mealCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Subsídio de Alimentação (€)')),
                  const Divider(),
                  TextField(controller: m1NormCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '1.ª Refeição Normal (€)')),
                  TextField(controller: m1PenCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '1.ª Refeição Penalizada (€)')),
                  const Divider(),
                  TextField(controller: m2NormCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '2.ª Refeição Normal (€)')),
                  TextField(controller: m2PenCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '2.ª Refeição Penalizada (€)')),
                  const Divider(),
                  const Text('Intervalo da Hora Noturna (+25%):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nStartCtrl,
                          readOnly: true,
                          onTap: () => pickNightTime(nStartCtrl),
                          decoration: const InputDecoration(labelText: 'Início', prefixIcon: Icon(Icons.nightlight_round, size: 18)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: nEndCtrl,
                          readOnly: true,
                          onTap: () => pickNightTime(nEndCtrl),
                          decoration: const InputDecoration(labelText: 'Fim', prefixIcon: Icon(Icons.wb_sunny_outlined, size: 18)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Definir como padrão para novos meses', style: TextStyle(fontSize: 12.5)),
                    value: applyToFutureMonths,
                    onChanged: (val) => setDState(() => applyToFutureMonths = val ?? true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                child: const Text('Guardar'),
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  final ym = _currentYmKey;

                  final b = double.tryParse(baseCtrl.text) ?? baseSalary;
                  final m = double.tryParse(mealCtrl.text) ?? mealAllowance;
                  final m1n = double.tryParse(m1NormCtrl.text) ?? firstMealNormal;
                  final m2n = double.tryParse(m2NormCtrl.text) ?? secondMealNormal;
                  final m1p = double.tryParse(m1PenCtrl.text) ?? firstMealPenalized;
                  final m2p = double.tryParse(m2PenCtrl.text) ?? secondMealPenalized;
                  final ns = nStartCtrl.text;
                  final ne = nEndCtrl.text;

                  await prefs.setDouble('base_salary_$ym', b);
                  await prefs.setDouble('meal_allowance_$ym', m);
                  await prefs.setDouble('first_meal_normal_$ym', m1n);
                  await prefs.setDouble('second_meal_normal_$ym', m2n);
                  await prefs.setDouble('first_meal_penalized_$ym', m1p);
                  await prefs.setDouble('second_meal_penalized_$ym', m2p);
                  await prefs.setString('night_start_$ym', ns);
                  await prefs.setString('night_end_$ym', ne);
                  await prefs.setString('driver_type_$ym', selectedType);

                  if (applyToFutureMonths) {
                    await prefs.setDouble('base_salary', b);
                    await prefs.setDouble('meal_allowance', m);
                    await prefs.setDouble('first_meal_normal', m1n);
                    await prefs.setDouble('second_meal_normal', m2n);
                    await prefs.setDouble('first_meal_penalized', m1p);
                    await prefs.setDouble('second_meal_penalized', m2p);
                    await prefs.setString('night_start', ns);
                    await prefs.setString('night_end', ne);
                    await prefs.setString('driver_type', selectedType);
                  }

                  setState(() {
                    baseSalary = b;
                    mealAllowance = m;
                    firstMealNormal = m1n;
                    secondMealNormal = m2n;
                    firstMealPenalized = m1p;
                    secondMealPenalized = m2p;
                    nightStart = ns;
                    nightEnd = ne;
                    driverType = selectedType;
                  });

                  _triggerAutoCloudSync();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              )
            ],
          );
        },
      ),
    );
  }

  void _openEntryEditor(DriverEntry? item, String targetDate) {
    final dateCtrl = TextEditingController(text: item?.date ?? targetDate);
    final vehCtrl = TextEditingController(text: item?.vehicleNumber ?? '');
    final startCtrl = TextEditingController(text: item?.startTime ?? '08:00');
    final endCtrl = TextEditingController(text: item?.endTime ?? '17:00');
    final i1StartCtrl = TextEditingController(text: item?.int1Start ?? '');
    final i1EndCtrl = TextEditingController(text: item?.int1End ?? '');
    final i2StartCtrl = TextEditingController(text: item?.int2Start ?? '');
    final i2EndCtrl = TextEditingController(text: item?.int2End ?? '');

    String dayType = item?.dayType ?? 'Util';
    bool mealAllowanceCheck = item?.hasMealAllowance ?? true;
    String firstMealOption = item?.firstMeal ?? 'Nenhuma';
    String secondMealOption = item?.secondMeal ?? 'Nenhuma';
    bool hasCollectionDay = item?.hasCollection ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          bool hasAnySpecialMeal = firstMealOption != 'Nenhuma' || secondMealOption != 'Nenhuma';
          if (hasAnySpecialMeal) {
            mealAllowanceCheck = false;
          }

          Future<void> selectTime(TextEditingController ctrl) async {
            TimeOfDay initial = const TimeOfDay(hour: 8, minute: 0);
            if (ctrl.text.contains(':')) {
              final parts = ctrl.text.split(':');
              initial = TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: int.tryParse(parts[1]) ?? 0);
            }
            final picked = await showTimePicker(context: context, initialTime: initial);
            if (picked != null) {
              final h = picked.hour.toString().padLeft(2, '0');
              final m = picked.minute.toString().padLeft(2, '0');
              setDState(() => ctrl.text = '$h:$m');
            }
          }

          return AlertDialog(
            title: Text(item == null ? 'Registar Serviço' : 'Editar Serviço'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: 'Data (AAAA-MM-DD)')),
                  DropdownButtonFormField<String>(
                    value: dayType,
                    items: const [
                      DropdownMenuItem(value: 'Util', child: Text('Dia Útil')),
                      DropdownMenuItem(value: 'Folga', child: Text('FOLGA (Descanso Gozado)')),
                      DropdownMenuItem(value: 'Ferias', child: Text('FÉRIAS (Dia de Férias)')),
                      DropdownMenuItem(value: 'Descanso', child: Text('DESCANSO (Trabalho na Folga)')),
                      DropdownMenuItem(value: 'Feriado', child: Text('Feriado (Trabalhado)')),
                      DropdownMenuItem(value: 'Baixa', child: Text('Baixa Médica')),
                      DropdownMenuItem(value: 'Falta', child: Text('Falta')),
                    ],
                    onChanged: (val) => setDState(() => dayType = val!),
                    decoration: const InputDecoration(labelText: 'Tipo de Dia'),
                  ),
                  if (dayType == 'Util' || dayType == 'Descanso' || dayType == 'Feriado') ...[
                    TextField(controller: vehCtrl, decoration: const InputDecoration(labelText: 'N.º da Viatura / Matrícula', prefixIcon: Icon(Icons.directions_bus))),
                    const SizedBox(height: 12),
                    const Text('Horário do Serviço:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: startCtrl,
                            readOnly: true,
                            onTap: () => selectTime(startCtrl),
                            decoration: const InputDecoration(labelText: 'Início Serviço', prefixIcon: Icon(Icons.access_time)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: endCtrl,
                            readOnly: true,
                            onTap: () => selectTime(endCtrl),
                            decoration: const InputDecoration(labelText: 'Fim Serviço', prefixIcon: Icon(Icons.access_time_filled)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('1.ª Intermitência (mín. 1h):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: i1StartCtrl,
                            readOnly: true,
                            onTap: () => selectTime(i1StartCtrl),
                            decoration: const InputDecoration(labelText: 'Início', hintText: '--:--'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: i1EndCtrl,
                            readOnly: true,
                            onTap: () => selectTime(i1EndCtrl),
                            decoration: const InputDecoration(labelText: 'Fim', hintText: '--:--'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setDState(() {
                            i1StartCtrl.clear();
                            i1EndCtrl.clear();
                          }),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('2.ª Intermitência (mín. 1h / máx. 3h total):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: i2StartCtrl,
                            readOnly: true,
                            onTap: () => selectTime(i2StartCtrl),
                            decoration: const InputDecoration(labelText: 'Início', hintText: '--:--'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: i2EndCtrl,
                            readOnly: true,
                            onTap: () => selectTime(i2EndCtrl),
                            decoration: const InputDecoration(labelText: 'Fim', hintText: '--:--'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setDState(() {
                            i2StartCtrl.clear();
                            i2EndCtrl.clear();
                          }),
                        )
                      ],
                    ),
                    if (driverType == 'Turismo') ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Serviço com Cobrança de Bilhetes', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('Aplica 20% sobre 8h de trabalho neste dia', style: TextStyle(fontSize: 11.5)),
                        value: hasCollectionDay,
                        onChanged: (val) => setDState(() => hasCollectionDay = val ?? false),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text('Regime de Refeições:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    DropdownButtonFormField<String>(
                      value: firstMealOption,
                      items: const [
                        DropdownMenuItem(value: 'Nenhuma', child: Text('1.ª Refeição: Nenhuma')),
                        DropdownMenuItem(value: 'Normal', child: Text('1.ª Refeição: Normal')),
                        DropdownMenuItem(value: 'Penalizada', child: Text('1.ª Refeição: Penalizada')),
                      ],
                      onChanged: (val) {
                        setDState(() {
                          firstMealOption = val!;
                          if (firstMealOption != 'Nenhuma') mealAllowanceCheck = false;
                        });
                      },
                      decoration: const InputDecoration(labelText: '1.ª Refeição'),
                    ),
                    DropdownButtonFormField<String>(
                      value: secondMealOption,
                      items: const [
                        DropdownMenuItem(value: 'Nenhuma', child: Text('2.ª Refeição: Nenhuma')),
                        DropdownMenuItem(value: 'Normal', child: Text('2.ª Refeição: Normal')),
                        DropdownMenuItem(value: 'Penalizada', child: Text('2.ª Refeição: Penalizada')),
                      ],
                      onChanged: (val) {
                        setDState(() {
                          secondMealOption = val!;
                          if (secondMealOption != 'Nenhuma') mealAllowanceCheck = false;
                        });
                      },
                      decoration: const InputDecoration(labelText: '2.ª Refeição'),
                    ),
                    CheckboxListTile(
                      title: Text(
                        'Subsídio de Alimentação',
                        style: TextStyle(color: hasAnySpecialMeal ? Colors.grey : Colors.black),
                      ),
                      subtitle: hasAnySpecialMeal
                          ? const Text('Incompatível com 1ª/2ª Refeição', style: TextStyle(fontSize: 11, color: Colors.orange))
                          : null,
                      value: mealAllowanceCheck,
                      onChanged: hasAnySpecialMeal
                          ? null
                          : (val) => setDState(() => mealAllowanceCheck = val ?? true),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (item != null)
                TextButton(
                  child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                  onPressed: () async {
                    if (item.id != null) {
                      await DBHelper.instance.deleteEntry(item.id!);
                    }
                    _triggerAutoCloudSync();
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadMonthRatesAndEntries();
                  },
                ),
              TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.pop(ctx)),
              ElevatedButton(
                child: const Text('Guardar'),
                onPressed: () async {
                  int toMinutes(String t) {
                    if (!t.contains(':')) return 0;
                    final p = t.split(':');
                    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
                  }

                  int startM = toMinutes(startCtrl.text);
                  int endM = toMinutes(endCtrl.text);
                  int amplitudeM = endM >= startM ? (endM - startM) : (endM + 1440 - startM);

                  int validIntermM = 0;

                  if (i1StartCtrl.text.isNotEmpty && i1EndCtrl.text.isNotEmpty) {
                    int i1s = toMinutes(i1StartCtrl.text);
                    int i1e = toMinutes(i1EndCtrl.text);
                    int dur1 = i1e >= i1s ? (i1e - i1s) : (i1e + 1440 - i1s);
                    if (dur1 >= 60) validIntermM += dur1;
                  }

                  if (i2StartCtrl.text.isNotEmpty && i2EndCtrl.text.isNotEmpty) {
                    int i2s = toMinutes(i2StartCtrl.text);
                    int i2e = toMinutes(i2EndCtrl.text);
                    int dur2 = i2e >= i2s ? (i2e - i2s) : (i2e + 1440 - i2s);
                    if (dur2 >= 60) validIntermM += dur2;
                  }

                  if (validIntermM > 180) validIntermM = 180;

                  int effectiveWorkM = (amplitudeM - validIntermM) > 0 ? (amplitudeM - validIntermM) : 0;
                  double effectiveWorkH = effectiveWorkM / 60.0;
                  double intermH = validIntermM / 60.0;

                  double regH = effectiveWorkH > 8.0 ? 8.0 : effectiveWorkH;
                  double otH = effectiveWorkH > 8.0 ? effectiveWorkH - 8.0 : 0.0;

                  double computedNightH = _calculateNightHours(startCtrl.text, endCtrl.text);

                  final entry = DriverEntry(
                    id: item?.id,
                    date: dateCtrl.text.trim(),
                    dayType: dayType,
                    vehicleNumber: (dayType == 'Folga' || dayType == 'Ferias' || dayType == 'Baixa' || dayType == 'Falta') ? '' : vehCtrl.text.trim(),
                    startTime: (dayType == 'Folga' || dayType == 'Ferias' || dayType == 'Baixa' || dayType == 'Falta') ? '' : startCtrl.text.trim(),
                    endTime: (dayType == 'Folga' || dayType == 'Ferias' || dayType == 'Baixa' || dayType == 'Falta') ? '' : endCtrl.text.trim(),
                    int1Start: i1StartCtrl.text.trim(),
                    int1End: i1EndCtrl.text.trim(),
                    int2Start: i2StartCtrl.text.trim(),
                    int2End: i2EndCtrl.text.trim(),
                    regularHours: (dayType == 'Baixa' || dayType == 'Falta' || dayType == 'Folga' || dayType == 'Ferias') ? 0.0 : regH,
                    overtimeHours: (dayType == 'Baixa' || dayType == 'Falta' || dayType == 'Folga' || dayType == 'Ferias') ? 0.0 : otH,
                    intermitenciaHours: (dayType == 'Folga' || dayType == 'Ferias') ? 0.0 : intermH,
                    nightHours: (dayType == 'Baixa' || dayType == 'Falta' || dayType == 'Folga' || dayType == 'Ferias') ? 0.0 : computedNightH,
                    hasMealAllowance: (dayType == 'Baixa' || dayType == 'Falta' || dayType == 'Folga' || dayType == 'Ferias' || hasAnySpecialMeal) ? false : mealAllowanceCheck,
                    firstMeal: (dayType == 'Baixa' || dayType == 'Falta' || dayType == 'Folga' || dayType == 'Ferias') ? 'Nenhuma' : firstMealOption,
                    secondMeal: (dayType == 'Baixa' || dayType == 'Falta' || dayType == 'Folga' || dayType == 'Ferias') ? 'Nenhuma' : secondMealOption,
                    hasCollection: (driverType == 'Turismo' && (dayType == 'Util' || dayType == 'Descanso' || dayType == 'Feriado')) ? hasCollectionDay : false,
                  );

                  await DBHelper.instance.insertOrUpdate(entry);
                  _triggerAutoCloudSync();
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadMonthRatesAndEntries();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}