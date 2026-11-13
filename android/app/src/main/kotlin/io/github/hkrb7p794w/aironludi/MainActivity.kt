package io.github.hkrb7p794w.aironludi

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity statt FlutterActivity: Health Connect fragt Berechtigungen über die
// Activity-Result-API an (Voraussetzung des Pakets `health`).
class MainActivity : FlutterFragmentActivity()
