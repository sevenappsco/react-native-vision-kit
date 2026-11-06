import { StatusBar } from "expo-status-bar";
import { useCallback, useState } from "react";
import { Platform, Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View } from "react-native";
import * as Translate from "@sevenappsco/vision-kit/translate";
import { runChecks, type CheckResult } from "./src/checks";
import { FaceCameraScreen } from "./src/FaceCameraScreen";
import { ModalSheetRepro } from "./src/ModalSheetRepro";

type Tab = "checks" | "camera";

export default function App() {
  const [tab, setTab] = useState<Tab>("checks");
  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="auto" />
      <View style={styles.tabs}>
        {(["checks", "camera"] as const).map((t) => (
          <Pressable key={t} onPress={() => setTab(t)} style={[styles.tab, tab === t && styles.tabActive]}>
            <Text style={styles.tabText}>{t === "checks" ? "Checks" : "Face camera"}</Text>
          </Pressable>
        ))}
      </View>
      <View style={{ flex: 1 }}>{tab === "checks" ? <ChecksScreen /> : <FaceCameraScreen />}</View>
    </SafeAreaView>
  );
}

function ChecksScreen() {
  const [results, setResults] = useState<CheckResult[]>([]);
  const [running, setRunning] = useState(false);
  const [downloadState, setDownloadState] = useState<string>("");

  const run = useCallback(async () => {
    setRunning(true);
    setResults([]);
    try {
      await runChecks((r) => setResults((prev) => [...prev, r]));
    } finally {
      setRunning(false);
      console.log("[vision-kit-check] DONE");
    }
  }, []);

  const download = useCallback(async () => {
    setDownloadState("requesting en→es…");
    try {
      const ok = await Translate.downloadLanguagePair("en", "es");
      setDownloadState(ok ? "downloaded en→es" : "declined / not downloaded");
    } catch (e: any) {
      setDownloadState(`${e?.code}: ${e?.message}`);
    }
  }, []);

  const passed = results.filter((r) => r.status === "pass").length;
  const failed = results.filter((r) => r.status === "fail").length;

  return (
    <ScrollView contentContainerStyle={styles.list}>
      <Text style={styles.title}>
        @sevenappsco/vision-kit · {Platform.OS} {String(Platform.Version)}
      </Text>
      <View style={styles.row}>
        <Pressable testID="run-checks" onPress={run} style={styles.button} disabled={running}>
          <Text style={styles.buttonText}>{running ? "Running…" : "Run checks"}</Text>
        </Pressable>
        {Translate.isTranslationSupported && (
          <Pressable testID="download-es" onPress={download} style={styles.button}>
            <Text style={styles.buttonText}>Download en→es</Text>
          </Pressable>
        )}
      </View>
      {!!downloadState && <Text style={styles.detail}>{downloadState}</Text>}
      {Platform.OS === "ios" && Translate.isTranslationSupported && <ModalSheetRepro />}
      {results.length > 0 && (
        <Text style={styles.summary}>
          {passed} passed · {failed} failed{running ? " · running" : ""}
        </Text>
      )}
      {results.map((r, i) => (
        <View key={i} style={styles.result}>
          <Text style={[styles.name, r.status === "pass" ? styles.pass : r.status === "fail" ? styles.fail : styles.info]}>
            {r.status === "pass" ? "✓" : r.status === "fail" ? "✗" : "ℹ"} {r.name}
            {r.ms != null ? `  ${r.ms} ms` : ""}
          </Text>
          <Text style={styles.detail}>{r.detail}</Text>
        </View>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#fff", paddingTop: Platform.OS === "android" ? 36 : 0 },
  tabs: { flexDirection: "row", borderBottomWidth: StyleSheet.hairlineWidth, borderColor: "#ccc" },
  tab: { flex: 1, padding: 12, alignItems: "center" },
  tabActive: { borderBottomWidth: 2, borderColor: "#0a7" },
  tabText: { fontWeight: "600" },
  list: { padding: 14, gap: 8 },
  title: { fontSize: 16, fontWeight: "700" },
  row: { flexDirection: "row", gap: 8 },
  button: { backgroundColor: "#0a7", paddingVertical: 10, paddingHorizontal: 14, borderRadius: 8 },
  buttonText: { color: "white", fontWeight: "600" },
  summary: { fontWeight: "700", marginTop: 4 },
  result: { borderTopWidth: StyleSheet.hairlineWidth, borderColor: "#ddd", paddingTop: 6 },
  name: { fontWeight: "600", fontSize: 13 },
  pass: { color: "#0a7" },
  fail: { color: "#c22" },
  info: { color: "#36c" },
  detail: { fontFamily: Platform.OS === "ios" ? "Menlo" : "monospace", fontSize: 11, color: "#333" },
});
