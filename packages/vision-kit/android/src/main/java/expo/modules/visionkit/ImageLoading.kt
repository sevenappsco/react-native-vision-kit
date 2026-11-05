package expo.modules.visionkit

import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.exception.Exceptions
import java.io.File

class ImageLoadException(uri: String, cause: Throwable?) :
  CodedException("ERR_IMAGE_LOAD", "Could not decode image at $uri", cause)

/**
 * `InputImage.fromFilePath` applies the EXIF rotation, so ML Kit returns
 * coordinates in the upright image, the same space as the iOS implementation.
 */
internal fun loadInputImage(appContext: AppContext, uri: String): InputImage {
  val context = appContext.reactContext ?: throw Exceptions.ReactContextLost()
  val parsed = if (uri.startsWith("/")) Uri.fromFile(File(uri)) else Uri.parse(uri)
  return try {
    InputImage.fromFilePath(context, parsed)
  } catch (e: Exception) {
    throw ImageLoadException(uri, e)
  }
}
