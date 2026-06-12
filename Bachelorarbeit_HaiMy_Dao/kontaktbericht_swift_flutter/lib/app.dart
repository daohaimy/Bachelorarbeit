import 'package:flutter/material.dart';
import 'package:kontaktbericht_swift_flutter/pages/kontaktbericht_list_page.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kontaktbericht',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const KontaktberichtListPage(),
    );
  }
}
