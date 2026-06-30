import 'package:flutter/material.dart';

class RePaperTodoApp extends StatelessWidget {
  const RePaperTodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RePaperTodo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B7CFA)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('RePaperTodo scaffold'),
        ),
      ),
    );
  }
}

