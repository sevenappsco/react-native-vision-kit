package com.margelo.nitro.visionkitcamera

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider

/** Only exists so RN autolinking loads the native library and registers the Nitro hybrid objects. */
class SevenAppsVisionKitCameraPackage : BaseReactPackage() {
  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? = null

  override fun getReactModuleInfoProvider(): ReactModuleInfoProvider = ReactModuleInfoProvider { HashMap() }

  companion object {
    init {
      SevenAppsVisionKitCameraOnLoad.initializeNative()
    }
  }
}
