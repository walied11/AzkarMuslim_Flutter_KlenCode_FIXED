import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AzkarMuslimApp());
}

class AppColors {
  static const bg = Color(0xFF0B1715);
  static const panel = Color(0xFF142522);
  static const panel2 = Color(0xFF1B302B);
  static const green = Color(0xFF4DC6A0);
  static const gold = Color(0xFFE7BD70);
  static const white = Color(0xFFF4F6F2);
  static const muted = Color(0xFFA8BBB4);
}

class AzkarMuslimApp extends StatelessWidget {
  const AzkarMuslimApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'أذكار وتحصين مسلم', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(primary: AppColors.green, secondary: AppColors.gold, surface: AppColors.panel),
      fontFamily: 'QuranFont', appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, foregroundColor: AppColors.white, centerTitle: true, elevation: 0),
    ), home: const UpdateGate(child: HomePage()));
}


/// Mandatory app-update gate backed by Firebase Realtime Database REST API.
/// Configure /app_update in the database (see update_config.example.json).
class UpdateGate extends StatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});
  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  static const String _updateConfigUrl =
      'https://walied-f4f1b-default-rtdb.firebaseio.com/app_update.json';
  bool _checking = true;
  bool _mustUpdate = false;
  bool _checkFailed = false;
  bool _busy = false;
  String _currentVersion = '1.0.0';
  String _latestVersion = '';
  String _releaseNotes = 'يتوفر إصدار جديد من التطبيق. حدّث التطبيق للمتابعة.';
  String _apkUrl = '';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  int _compareVersions(String a, String b) {
    List<int> parts(String value) => value
        .split('+')
        .first
        .split('-')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final aa = parts(a);
    final bb = parts(b);
    final length = aa.length > bb.length ? aa.length : bb.length;
    for (var i = 0; i < length; i++) {
      final av = i < aa.length ? aa[i] : 0;
      final bv = i < bb.length ? bb[i] : 0;
      if (av < bv) return -1;
      if (av > bv) return 1;
    }
    return 0;
  }

  Future<void> _checkForUpdate() async {
    if (mounted) {
      setState(() {
        _checking = true;
        _checkFailed = false;
        _errorMessage = '';
      });
    }
    try {
      final package = await PackageInfo.fromPlatform();
      _currentVersion = package.version;
      final currentBuildCode = int.tryParse(package.buildNumber) ?? 0;
      final response = await http
          .get(Uri.parse(_updateConfigUrl))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('تعذر الوصول إلى إعدادات التحديث (${response.statusCode})');
      }
      final body = response.body.trim();
      if (body.isEmpty || body == 'null') {
        throw Exception('لم يتم إعداد بيانات التحديث في Firebase بعد.');
      }
      final config = jsonDecode(body) as Map<String, dynamic>;
      _latestVersion = (config['latestVersion'] ??
          config['latest_version_name'] ??
          config['latest_version_code'] ?? '').toString();
      final minVersion = (config['minVersion'] ??
          config['min_version_name'] ?? '0.0.0').toString();
      final latestCode = int.tryParse(
          (config['latest_version_code'] ?? '').toString());
      final minCode = int.tryParse(
          (config['min_version_code'] ?? '').toString());
      final updateUrl = (config['update_url'] ?? config['apkUrl'] ?? '').toString().trim();
      final forceUpdate = config['update_force'] == true ||
          config['forceUpdate'] == true;
      _apkUrl = updateUrl;
      _releaseNotes = (config['releaseNotes'] ??
              config['update_message'] ??
              'يتوفر إصدار جديد من التطبيق. حدّث التطبيق للمتابعة.')
          .toString();
      final minVersionCode = minCode ?? 0;
      final latestVersionCode = latestCode ?? 0;
      final belowMinimum = (minVersionCode > 0 && currentBuildCode < minVersionCode) ||
          _compareVersions(_currentVersion, minVersion) < 0;
      final newerAvailable = (latestVersionCode > 0 && currentBuildCode < latestVersionCode) ||
          (_latestVersion.isNotEmpty &&
           _compareVersions(_currentVersion, _latestVersion) < 0);
      if (mounted) {
        setState(() {
          _mustUpdate = belowMinimum || (forceUpdate && newerAvailable);
          _checking = false;
          _checkFailed = false;
        });
      }
    } catch (e) {
      // Fail closed: mandatory-update mode cannot be verified without the server.
      if (mounted) {
        setState(() {
          _checking = false;
          _checkFailed = true;
          _errorMessage = 'تعذر التحقق من التحديث. تأكد من الإنترنت ثم أعد المحاولة.';
        });
      }
    }
  }

  Future<void> _openDownload() async {
    if (_apkUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم إضافة رابط تنزيل APK في Firebase بعد.')),
      );
      return;
    }
    final uri = Uri.tryParse(_apkUrl);
    if (uri == null || uri.scheme != 'https' && uri.scheme != 'http') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رابط التحديث غير صحيح.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح رابط التحديث.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text('جارٍ التحقق من تحديث التطبيق...', style: TextStyle(color: AppColors.white)),
        ])),
      );
    }
    if (_checkFailed) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: Padding(padding: const EdgeInsets.all(26), child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.gold, size: 62),
            const SizedBox(height: 18),
            const Text('تعذر التحقق من التحديث', textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.white, fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(_errorMessage, textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.7)),
            const SizedBox(height: 22),
            FilledButton.icon(onPressed: _checkForUpdate,
                icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
          ],
        ))),
      );
    }
    if (_mustUpdate) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(child: SingleChildScrollView(child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 100, height: 100,
                decoration: BoxDecoration(color: AppColors.green.withOpacity(.13), shape: BoxShape.circle),
                child: const Icon(Icons.system_update_alt_rounded, color: AppColors.green, size: 54)),
              const SizedBox(height: 24),
              const Text('تحديث إجباري', textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.white, fontSize: 27, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('يجب تحديث التطبيق إلى أحدث إصدار قبل المتابعة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 16, height: 1.8)),
              if (_latestVersion.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('الإصدار الحالي: $_currentVersion  •  الجديد: $_latestVersion',
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gold)),
              ],
              if (_releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(_releaseNotes, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.white, height: 1.7)),
              ],
              const SizedBox(height: 26),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: _busy ? null : _openDownload,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded),
                label: const Text('تحديث الآن'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              )),
              const SizedBox(height: 10),
              TextButton(onPressed: _checkForUpdate, child: const Text('تحقّق مرة أخرى')),
            ]),
          ))),
        ),
      );
    }
    return widget.child;
  }
}

class DataStore {
  static List<Map<String, dynamic>> sections = [];
  static List<Map<String, dynamic>> ayahs = [];
  static Future<void> load() async {
    if (sections.isEmpty) {
      final a = jsonDecode(await rootBundle.loadString('assets/azkar.json')) as Map<String,dynamic>;
      sections = List<Map<String,dynamic>>.from((a['sections'] as List).map((e)=>Map<String,dynamic>.from(e)));
      final q = jsonDecode(await rootBundle.loadString('assets/quran.json')) as Map<String,dynamic>;
      ayahs = List<Map<String,dynamic>>.from((q['ayahs'] as List).map((e)=>Map<String,dynamic>.from(e)));
    }
  }
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage> {
  int tab=0; String greeting='';
  @override void initState(){super.initState(); final h=DateTime.now().hour; greeting=h<12?'صباح الخير':h<18?'مساء الخير':'مساء النور';}
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('أذكار وتحصين مسلم',style:TextStyle(fontWeight:FontWeight.bold)), actions:[IconButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const FavoritesPage())),icon:const Icon(Icons.favorite_border))]),
    body: FutureBuilder<void>(future:DataStore.load(),builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator()); return IndexedStack(index:tab,children:[_home(),const AzkarSectionsPage(),const QuranPage()]);}),
    bottomNavigationBar: NavigationBar(backgroundColor:AppColors.panel,indicatorColor:AppColors.green.withOpacity(.18),selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'الرئيسية'),NavigationDestination(icon:Icon(Icons.spa_outlined),selectedIcon:Icon(Icons.spa),label:'الأذكار'),NavigationDestination(icon:Icon(Icons.menu_book_outlined),selectedIcon:Icon(Icons.menu_book),label:'القرآن')]),
  );
  Widget _home()=>ListView(padding:const EdgeInsets.all(18),children:[
    Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF1C5142),Color(0xFF18352E)],begin:Alignment.topRight,end:Alignment.bottomLeft),borderRadius:BorderRadius.circular(24),border:Border.all(color:AppColors.green.withOpacity(.35))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.nights_stay_outlined,color:AppColors.gold,size:32),const SizedBox(height:16),Text(greeting,style:const TextStyle(color:AppColors.gold,fontSize:16)),const SizedBox(height:7),const Text('طمئن قلبك بذكر الله',style:TextStyle(fontSize:25,fontWeight:FontWeight.bold)),const SizedBox(height:10),const Text('﴿ أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ ﴾',textAlign:TextAlign.right,style:TextStyle(fontSize:20,height:1.8)),const Text('سورة الرعد · ٢٨',style:TextStyle(color:AppColors.muted))]),),
    const SizedBox(height:24),const Text('ابدأ رحلتك',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:12),
    _homeTile(Icons.wb_sunny_outlined,'أذكار الصباح','ابدأ يومك بذكر الله',()=>_openSectionById('morning')),
    _homeTile(Icons.nights_stay_outlined,'أذكار المساء','اختم يومك بالطمأنينة',()=>_openSectionById('evening')),
    _homeTile(Icons.menu_book,'القرآن الكريم','اقرأ آيات القرآن الكريم',()=>setState(()=>tab=2)),
    _homeTile(Icons.shield_outlined,'الأذكار والتحصين','مجموعة الأذكار اليومية',()=>setState(()=>tab=1)),
    const SizedBox(height:12),const Center(child:Text('اللهم اجعل القرآن ربيع قلوبنا',style:TextStyle(color:AppColors.muted,fontSize:15))),
  ]);
  Widget _homeTile(IconData icon,String title,String subtitle,VoidCallback tap)=>Card(color:AppColors.panel,elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18),side:BorderSide(color:Colors.white.withOpacity(.05))),child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:8),leading:Container(width:48,height:48,decoration:BoxDecoration(color:AppColors.green.withOpacity(.13),borderRadius:BorderRadius.circular(14)),child:Icon(icon,color:AppColors.green)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(subtitle,style:const TextStyle(color:AppColors.muted)),trailing:const Icon(Icons.chevron_left,color:AppColors.gold),onTap:tap));
  void _openSectionById(String id){final i=DataStore.sections.indexWhere((e)=>e['id']==id);if(i>=0)Navigator.push(context,MaterialPageRoute(builder:(_)=>AzkarReaderPage(section:DataStore.sections[i])));else setState(()=>tab=1);}
}

class AzkarSectionsPage extends StatefulWidget {const AzkarSectionsPage({super.key});@override State<AzkarSectionsPage> createState()=>_AzkarSectionsPageState();}
class _AzkarSectionsPageState extends State<AzkarSectionsPage>{String query='';@override Widget build(BuildContext context){final sections=DataStore.sections.where((s)=>(s['title']??'').toString().contains(query)||(s['description']??'').toString().contains(query)).toList();return Column(children:[Padding(padding:const EdgeInsets.fromLTRB(16,8,16,12),child:TextField(onChanged:(v)=>setState(()=>query=v),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'ابحث عن قسم الأذكار',filled:true,fillColor:AppColors.panel,border:OutlineInputBorder(borderRadius:BorderRadius.all(Radius.circular(16)),borderSide:BorderSide.none)))),Expanded(child:ListView.builder(padding:const EdgeInsets.symmetric(horizontal:16),itemCount:sections.length,itemBuilder:(context,i){final s=sections[i];final color=Color(int.tryParse('FF'+(s['color']??'4DC6A0').toString().replaceAll('#',''),radix:16)??0xFF4DC6A0);return Card(color:AppColors.panel,elevation:0,margin:const EdgeInsets.only(bottom:10),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),child:ListTile(contentPadding:const EdgeInsets.all(12),leading:CircleAvatar(backgroundColor:color.withOpacity(.16),child:const Icon(Icons.auto_awesome,color:AppColors.gold)),title:Text(s['title']??'الأذكار',style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${s['description']??''}\n${(s['items'] as List? ?? []).length} ذكر',style:const TextStyle(color:AppColors.muted,height:1.6)),isThreeLine:true,trailing:const Icon(Icons.chevron_left),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>AzkarReaderPage(section:s))).then((_){if(mounted)setState((){});})));}))]);}}

class AzkarReaderPage extends StatefulWidget {final Map<String,dynamic> section;const AzkarReaderPage({super.key,required this.section});@override State<AzkarReaderPage> createState()=>_AzkarReaderPageState();}
class _AzkarReaderPageState extends State<AzkarReaderPage> {
  late List items;
  late List<int> counts;
  Set<String> favorites = {};

  @override
  void initState() {
    super.initState();
    items = List.from(widget.section['items'] as List? ?? []);
    counts = items.map<int>((_) => 0).toList();
    _loadFav();
  }

  String _key(Map e) => '${e['title'] ?? ''}|${e['text'] ?? ''}';

  Future<void> _loadFav() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => favorites = (p.getStringList('favorites') ?? []).toSet());
  }

  Future<void> _toggleFav(Map e) async {
    final p = await SharedPreferences.getInstance();
    final k = _key(e);
    setState(() { if (favorites.contains(k)) { favorites.remove(k); } else { favorites.add(k); } });
    await p.setStringList('favorites', favorites.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.section['title'] ?? 'الأذكار')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.section['verse'] != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.panel2, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Text(widget.section['verse'], textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gold, fontSize: 19, height: 1.9)),
                Text(widget.section['verseReference'] ?? '', style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
          const SizedBox(height: 12),
          ...List.generate(items.length, (i) {
            final e = Map<String, dynamic>.from(items[i] as Map);
            final target = (e['count'] as num?)?.toInt() ?? 1;
            final done = counts[i] >= target;
            final isFavorite = favorites.contains(_key(e));
            return Card(
              color: AppColors.panel,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: done ? AppColors.green.withOpacity(.45) : Colors.white.withOpacity(.04)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(e['title'] ?? 'ذكر', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 16))),
                    IconButton(onPressed: () => _toggleFav(e), icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? Colors.pinkAccent : AppColors.muted)),
                    IconButton(onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: e['text'] ?? ''));
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الذكر')));
                    }, icon: const Icon(Icons.copy_outlined, color: AppColors.muted)),
                  ]),
                  const SizedBox(height: 8),
                  Text(e['text'] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, height: 2.0, color: AppColors.white)),
                  if (e['source'] != null)
                    Padding(padding: const EdgeInsets.only(top: 12), child: Text(e['source'], textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Text(done ? 'اكتمل الذكر' : 'التكرار: ${counts[i]} / $target', style: TextStyle(color: done ? AppColors.green : AppColors.muted))),
                    IconButton(onPressed: counts[i] > 0 ? () => setState(() => counts[i]--) : null, icon: const Icon(Icons.remove_circle_outline)),
                    FilledButton.icon(onPressed: done ? null : () => setState(() => counts[i]++), icon: Icon(done ? Icons.check : Icons.touch_app), label: Text(done ? 'تم' : 'سبّح')),
                  ]),
                ]),
              ),
            );
          }),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => counts = items.map<int>((_) => 0).toList()),
        icon: const Icon(Icons.restart_alt), label: const Text('إعادة العداد'),
      ),
    );
  }
}

class QuranPage extends StatefulWidget{const QuranPage({super.key});@override State<QuranPage> createState()=>_QuranPageState();}
class _QuranPageState extends State<QuranPage>{String query='';final names=['الفاتحة','البقرة','آل عمران','النساء','المائدة','الأنعام','الأعراف','الأنفال','التوبة','يونس','هود','يوسف','الرعد','إبراهيم','الحجر','النحل','الإسراء','الكهف','مريم','طه','الأنبياء','الحج','المؤمنون','النور','الفرقان','الشعراء','النمل','القصص','العنكبوت','الروم','لقمان','السجدة','الأحزاب','سبأ','فاطر','يس','الصافات','ص','الزمر','غافر','فصلت','الشورى','الزخرف','الدخان','الجاثية','الأحقاف','محمد','الفتح','الحجرات','ق','الذاريات','الطور','النجم','القمر','الرحمن','الواقعة','الحديد','المجادلة','الحشر','الممتحنة','الصف','الجمعة','المنافقون','التغابن','الطلاق','التحريم','الملك','القلم','الحاقة','المعارج','نوح','الجن','المزمل','المدثر','القيامة','الإنسان','المرسلات','النبأ','النازعات','عبس','التكوير','الانفطار','المطففين','الانشقاق','البروج','الطارق','الأعلى','الغاشية','الفجر','البلد','الشمس','الليل','الضحى','الشرح','التين','العلق','القدر','البينة','الزلزلة','العاديات','القارعة','التكاثر','العصر','الهمزة','الفيل','قريش','الماعون','الكوثر','الكافرون','النصر','المسد','الإخلاص','الفلق','الناس'];
@override Widget build(BuildContext context){return Column(children:[Padding(padding:const EdgeInsets.fromLTRB(16,8,16,12),child:TextField(onChanged:(v)=>setState(()=>query=v),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'ابحث عن سورة',filled:true,fillColor:AppColors.panel,border:OutlineInputBorder(borderRadius:BorderRadius.all(Radius.circular(16)),borderSide:BorderSide.none)))),Expanded(child:ListView.builder(padding:const EdgeInsets.symmetric(horizontal:16),itemCount:114,itemBuilder:(context,i){final n=i+1;final name=names[i];if(query.isNotEmpty&&!name.contains(query)&&!n.toString().contains(query))return const SizedBox.shrink();final count=DataStore.ayahs.where((a)=>a['surah']==n).length;return Card(color:AppColors.panel,elevation:0,margin:const EdgeInsets.only(bottom:7),child:ListTile(leading:Container(width:42,height:42,alignment:Alignment.center,decoration:BoxDecoration(color:AppColors.green.withOpacity(.12),borderRadius:BorderRadius.circular(12)),child:Text('$n',style:const TextStyle(color:AppColors.gold,fontWeight:FontWeight.bold))),title:Text(name,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('$count آية',style:const TextStyle(color:AppColors.muted)),trailing:const Icon(Icons.chevron_left),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SurahPage(number:n,name:name)))));} ))]);}}

class SurahPage extends StatelessWidget{final int number;final String name;const SurahPage({super.key,required this.number,required this.name});@override Widget build(BuildContext context){final ayahs=DataStore.ayahs.where((a)=>a['surah']==number).toList();return Scaffold(appBar:AppBar(title:Text('سورة $name')),body:ListView(padding:const EdgeInsets.all(18),children:[Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:AppColors.panel2,borderRadius:BorderRadius.circular(18)),child:Column(children:[Text('سُورَةُ $name',style:const TextStyle(color:AppColors.gold,fontSize:24,fontWeight:FontWeight.bold)),if(number!=1&&number!=9)const Padding(padding:EdgeInsets.only(top:16),child:Text('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',textAlign:TextAlign.center,style:TextStyle(fontSize:22,height:2)))])),const SizedBox(height:12),Wrap(alignment:WrapAlignment.center,spacing:5,runSpacing:8,children:ayahs.map((a)=>Text('${a['text']} ﴿${a['ayah']}﴾',textAlign:TextAlign.center,style:const TextStyle(fontSize:23,height:2.2,color:AppColors.white))).toList())]));}}

class FavoritesPage extends StatefulWidget{const FavoritesPage({super.key});@override State<FavoritesPage> createState()=>_FavoritesPageState();}
class _FavoritesPageState extends State<FavoritesPage>{List<String> favorites=[];@override void initState(){super.initState();_load();}Future<void> _load()async{final p=await SharedPreferences.getInstance();if(mounted)setState(()=>favorites=p.getStringList('favorites')??[]);}@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('الأذكار المفضلة')),body:favorites.isEmpty?const Center(child:Text('لم تضف أذكارًا للمفضلة بعد',style:TextStyle(color:AppColors.muted))):ListView.builder(itemCount:favorites.length,itemBuilder:(context,i){final bits=favorites[i].split('|');return Card(color:AppColors.panel,margin:const EdgeInsets.symmetric(horizontal:14,vertical:6),child:ListTile(title:Text(bits.first,style:const TextStyle(color:AppColors.gold)),subtitle:Text(bits.length>1?bits.sublist(1).join('|'):'',maxLines:4,overflow:TextOverflow.ellipsis,style:const TextStyle(height:1.7)),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{final p=await SharedPreferences.getInstance();favorites.removeAt(i);await p.setStringList('favorites',favorites);setState((){});})));}));}