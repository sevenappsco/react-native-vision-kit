package expo.modules.visionkit

import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class LanguageUnsupportedException(code: String) :
  CodedException("ERR_LANGUAGE_UNSUPPORTED", "ML Kit Translate does not support $code", null)

class ModelNotDownloadedException(pair: String) :
  CodedException("ERR_MODEL_NOT_DOWNLOADED", "Translation models for $pair are not downloaded", null)

class TranslationFailedException(message: String, cause: Throwable?) :
  CodedException("ERR_TRANSLATION_FAILED", message, cause)

/** Offline translation with ML Kit Translate. Same JS surface as the iOS (Apple Translation) module. */
class VisionKitTranslateModule : Module() {
  private val modelManager by lazy { RemoteModelManager.getInstance() }
  private var cached: Pair<String, Translator>? = null

  override fun definition() = ModuleDefinition {
    Name("VisionKitTranslate")

    Constant("isSupported") { true }
    Constant("canDeleteLanguageModels") { true }
    Constant("canDownloadSilently") { true }

    AsyncFunction("getSupportedLanguages") { TranslateLanguage.getAllLanguages().sorted() }

    AsyncFunction("getPairStatus") { source: String, target: String ->
      val s = mlLanguage(source, throwIfMissing = false)
      val t = mlLanguage(target, throwIfMissing = false)
      if (s == null || t == null || s == t) return@AsyncFunction "unsupported"
      val downloaded = downloadedModels()
      if (s in downloaded && t in downloaded) "downloaded" else "downloadable"
    }

    AsyncFunction("getDownloadedLanguageModels") { downloadedModels().sorted() }

    AsyncFunction("isLanguageDownloaded") { code: String ->
      mlLanguage(code) in downloadedModels()
    }

    AsyncFunction("downloadLanguagePair") { source: String, target: String ->
      download(mlLanguage(source)!!)
      download(mlLanguage(target)!!)
      true
    }

    AsyncFunction("downloadLanguageModel") { code: String ->
      download(mlLanguage(code)!!)
      true
    }

    AsyncFunction("deleteLanguageModel") { code: String ->
      val language = mlLanguage(code)!!
      if (language == TranslateLanguage.ENGLISH) return@AsyncFunction false // built into ML Kit
      closeCached()
      Tasks.await(modelManager.deleteDownloadedModel(TranslateRemoteModel.Builder(language).build()))
      true
    }

    AsyncFunction("translateBatch") { texts: List<String>, source: String, target: String, downloadIfNeeded: Boolean ->
      if (texts.isEmpty()) return@AsyncFunction emptyList<String>()
      val s = mlLanguage(source)!!
      val t = mlLanguage(target)!!
      val downloaded = downloadedModels()
      if (s !in downloaded || t !in downloaded) {
        if (!downloadIfNeeded) throw ModelNotDownloadedException("$source → $target")
        download(s)
        download(t)
      }
      val translator = translator(s, t)
      try {
        texts.map { Tasks.await(translator.translate(it)) }
      } catch (e: Exception) {
        val message = e.cause?.message ?: e.message ?: "Translation failed"
        // ML Kit's registry can claim a model exists after its files are gone.
        if (message.contains("model files not found", ignoreCase = true)) {
          throw ModelNotDownloadedException("$source → $target")
        }
        throw TranslationFailedException(message, e)
      }
    }

    OnDestroy { closeCached() }
  }

  private fun mlLanguage(code: String, throwIfMissing: Boolean = true): String? {
    val base = code.substringBefore('-').substringBefore('_').lowercase()
    val normalized = when (base) {
      "nb", "nn" -> "no"
      "iw" -> "he"
      "fil" -> "tl"
      else -> base
    }
    val language = TranslateLanguage.fromLanguageTag(normalized)
    if (language == null && throwIfMissing) throw LanguageUnsupportedException(code)
    return language
  }

  private fun downloadedModels(): Set<String> =
    Tasks.await(modelManager.getDownloadedModels(TranslateRemoteModel::class.java))
      .map { it.language }
      .toSet() + TranslateLanguage.ENGLISH

  private fun download(language: String) {
    if (language == TranslateLanguage.ENGLISH) return
    val model = TranslateRemoteModel.Builder(language).build()
    Tasks.await(modelManager.download(model, DownloadConditions.Builder().build()))
  }

  @Synchronized
  private fun translator(source: String, target: String): Translator {
    val key = "$source>$target"
    cached?.let { if (it.first == key) return it.second }
    closeCached()
    val translator = Translation.getClient(
      TranslatorOptions.Builder().setSourceLanguage(source).setTargetLanguage(target).build()
    )
    cached = key to translator
    return translator
  }

  @Synchronized
  private fun closeCached() {
    cached?.second?.close()
    cached = null
  }
}
