import 'dart:io';

/// Name des Gesundheitsspeichers des Telefons: Health Connect unter Android, Apple Health auf dem iPhone. Texte
/// nennen so nie eine Plattform, die das Gerät gar nicht hat.
String get healthStoreName => healthStoreNameOverride ?? (Platform.isAndroid ? 'Health Connect' : 'Apple Health');

/// Für Tests.
String? healthStoreNameOverride;
