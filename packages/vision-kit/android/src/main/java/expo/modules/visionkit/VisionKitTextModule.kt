package expo.modules.visionkit

import android.graphics.Rect
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

class RecognizeTextOptions : Record {
  @Field val languages: List<String>? = null
  @Field val level: String? = null
  @Field val languageCorrection: Boolean? = null
}

class ScriptUnsupportedException(script: String) :
  CodedException("ERR_SCRIPT_UNSUPPORTED", "Script '$script' is not supported by ML Kit text recognition on Android", null)

/** OCR with ML Kit Text Recognition v2. Same output shape as the iOS (Apple Vision) implementation. */
class VisionKitTextModule : Module() {
  private val recognizers = mutableMapOf<String, TextRecognizer>()

  override fun definition() = ModuleDefinition {
    Name("VisionKitText")

    Function("getSupportedScripts") { SCRIPTS }
    Function("getSupportedRecognitionLanguages") { _: String? -> emptyList<String>() }

    AsyncFunction("recognizeText") { uri: String, script: String, _: RecognizeTextOptions ->
      val recognizer = recognizer(script)
      val image = loadInputImage(appContext, uri)
      val text = Tasks.await(recognizer.process(image))
      text.toRecord()
    }

    OnDestroy {
      recognizers.values.forEach { it.close() }
      recognizers.clear()
    }
  }

  @Synchronized
  private fun recognizer(script: String): TextRecognizer {
    if (script !in SCRIPTS) throw ScriptUnsupportedException(script)
    return recognizers.getOrPut(script) {
      when (script) {
        "chinese" -> TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        "devanagari" -> TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
        "japanese" -> TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
        "korean" -> TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
        else -> TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
      }
    }
  }

  companion object {
    val SCRIPTS = listOf("latin", "chinese", "japanese", "korean", "devanagari")
  }
}

private fun Rect?.toFrame(): Map<String, Double> {
  val r = this ?: Rect()
  return mapOf(
    "left" to r.left.toDouble(),
    "top" to r.top.toDouble(),
    "right" to r.right.toDouble(),
    "bottom" to r.bottom.toDouble(),
  )
}

private fun languages(code: String): List<String> =
  if (code.isEmpty() || code == "und") emptyList() else listOf(code)

private fun Text.toRecord(): Map<String, Any> = mapOf(
  "text" to text,
  "blocks" to textBlocks.map { block ->
    mapOf(
      "text" to block.text,
      "frame" to block.boundingBox.toFrame(),
      "recognizedLanguages" to languages(block.recognizedLanguage),
      "lines" to block.lines.map { line ->
        mapOf(
          "text" to line.text,
          "frame" to line.boundingBox.toFrame(),
          "recognizedLanguages" to languages(line.recognizedLanguage),
          "elements" to line.elements.map { element ->
            mapOf(
              "text" to element.text,
              "frame" to element.boundingBox.toFrame(),
              "recognizedLanguages" to languages(element.recognizedLanguage),
            )
          },
        )
      },
    )
  },
)
