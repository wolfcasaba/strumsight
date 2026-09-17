package com.wolfcasaba.strumsight

import com.wolfcasaba.strumsight.audio.AudioDecoderChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var audioDecoderChannel: AudioDecoderChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioDecoderChannel =
            AudioDecoderChannel(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        audioDecoderChannel?.dispose()
        audioDecoderChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
