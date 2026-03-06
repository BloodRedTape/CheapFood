import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'cubit/scrape_cubit.dart';
import 'screens/menu_scrape_screen.dart';

void main() {
  runApp(const CheapFoodApp());
}

class CheapFoodApp extends StatelessWidget {
  const CheapFoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'CheapFood',
      home: BlocProvider(
        create: (_) => ScrapeCubit(),
        child: const MenuScrapeScreen(),
      ),
    );
  }
}
