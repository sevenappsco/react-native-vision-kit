import { useMemo, useRef, useState } from "react";
import { StyleSheet, Text, View } from "react-native";
import { Camera, useCameraDevice, useCameraPermission } from "react-native-vision-camera";
import { createFaceDetectorOutput, type Face } from "@sevenappsco/vision-kit-camera";

/** Mirrors skincare's faceScanModal usage of `createFaceDetectorOutput`. */
export function FaceCameraScreen() {
  const device = useCameraDevice("front");
  const { hasPermission, requestPermission } = useCameraPermission();
  const [faces, setFaces] = useState<Face[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [fps, setFps] = useState(0);
  const counter = useRef({ n: 0, t: Date.now() });

  const output = useMemo(
    () =>
      createFaceDetectorOutput({
        cameraFacing: "front",
        performanceMode: "fast",
        runLandmarks: false,
        runContours: false,
        runClassifications: false,
        onFacesDetected: (detected) => {
          const c = counter.current;
          c.n += 1;
          const now = Date.now();
          if (now - c.t >= 1000) {
            setFps(c.n);
            setFaces(detected.map((f) => ({ ...f, bounds: { ...f.bounds } })));
            console.log(`[vision-kit-camera] ${c.n} callbacks/s, faces=${detected.length}`, JSON.stringify(detected[0] ?? null));
            c.n = 0;
            c.t = now;
          }
        },
        onError: (e) => setError(String(e?.message ?? e)),
      }),
    [],
  );

  if (!hasPermission) {
    return (
      <View style={styles.center}>
        <Text style={styles.text} onPress={requestPermission}>
          Tap to grant camera permission
        </Text>
      </View>
    );
  }
  if (device == null) {
    return (
      <View style={styles.center}>
        <Text style={styles.text}>No front camera on this device (expected on the iOS simulator).</Text>
      </View>
    );
  }

  const f = faces[0];
  return (
    <View style={StyleSheet.absoluteFill}>
      <Camera style={StyleSheet.absoluteFill} device={device} isActive outputs={[output]} />
      <View style={styles.hud}>
        <Text style={styles.hudText}>
          callbacks/s: {fps} · faces: {faces.length}
          {f
            ? `\nbounds ${Math.round(f.bounds.x)},${Math.round(f.bounds.y)} ${Math.round(f.bounds.width)}×${Math.round(
                f.bounds.height,
              )} in ${f.frameWidth}×${f.frameHeight}\nroll ${f.rollAngle.toFixed(1)}° yaw ${f.yawAngle.toFixed(1)}°`
            : ""}
          {error ? `\nerror: ${error}` : ""}
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 24 },
  text: { fontSize: 16, textAlign: "center" },
  hud: { position: "absolute", left: 12, right: 12, bottom: 24, backgroundColor: "rgba(0,0,0,0.6)", borderRadius: 8, padding: 10 },
  hudText: { color: "white", fontFamily: "Menlo", fontSize: 12 },
});
