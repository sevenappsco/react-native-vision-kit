import { useCallback, useState } from "react";
import { Alert, Modal, Pressable, StyleSheet, Text, View } from "react-native";
import { requireNativeModule } from "expo";

// Repro for "Apple's download sheet never shows when called from a modal".
// Calls the hidden SwiftUI host with prepareTranslation() (shows the system
// sheet on the simulator) from no modal, an RN <Modal>, and a modal over a modal.
type Native = { debugHostRoundTrip(s: string, t: string, prepare: boolean, attachToRoot?: boolean): Promise<string> };
const native = requireNativeModule<Native>("VisionKitTranslate");

function useSheetCall(label: string, attachToRoot = false) {
  const [state, setState] = useState("");
  const call = useCallback(async () => {
    const start = Date.now();
    setState("waiting…");
    console.log(`[vision-kit-modal] ${label}: start`);
    try {
      const report = await native.debugHostRoundTrip("en", "es", true, attachToRoot);
      setState(`${report} (${Date.now() - start} ms)`);
      console.log(`[vision-kit-modal] ${label}: resolved ${report} (${Date.now() - start} ms)`);
    } catch (e: any) {
      setState(`${e?.code}: ${e?.message} (${Date.now() - start} ms)`);
      console.log(`[vision-kit-modal] ${label}: rejected ${e?.code}: ${e?.message} (${Date.now() - start} ms)`);
      if (attachToRoot) {
        // The host must not stay wedged after a watchdog rejection: the next normal job runs.
        const report = await native.debugHostRoundTrip("en", "es", false).catch((err: any) => `failed ${err?.code}`);
        console.log(`[vision-kit-modal] ${label}: next job after rejection → ${report}`);
      }
    }
  }, [label, attachToRoot]);
  return [state, call] as const;
}

function SheetButton({
  label,
  testID,
  underAlert,
  attachToRoot,
}: {
  label: string;
  testID: string;
  underAlert?: boolean;
  /** 0.1.1 behaviour (host under the root VC): the sheet is dropped, the watchdog must reject. */
  attachToRoot?: boolean;
}) {
  const [state, call] = useSheetCall(label, attachToRoot);
  // underAlert: request the sheet while a native alert is up (UIKit can't present
  // from an alert), to exercise the "sheet never appeared" watchdog.
  const onPress = underAlert
    ? () => {
        Alert.alert("Blocking alert", "The sheet request fires while this is up.", [{ text: "OK" }]);
        setTimeout(call, 800);
      }
    : call;
  return (
    <View style={{ gap: 4 }}>
      <Pressable testID={testID} onPress={onPress} style={styles.button}>
        <Text style={styles.buttonText}>prepareTranslation ({label})</Text>
      </Pressable>
      {!!state && <Text style={styles.detail}>{state}</Text>}
    </View>
  );
}

export function ModalSheetRepro() {
  const [outer, setOuter] = useState(false);
  const [inner, setInner] = useState(false);
  return (
    <View style={{ gap: 8 }}>
      <SheetButton label="no modal" testID="sheet-root" />
      <SheetButton label="under alert" testID="sheet-alert" underAlert />
      <SheetButton label="under alert, host on root (0.1.1)" testID="sheet-alert-root" underAlert attachToRoot />
      <Pressable testID="open-modal" onPress={() => setOuter(true)} style={styles.button}>
        <Text style={styles.buttonText}>Open RN Modal</Text>
      </Pressable>
      <Modal visible={outer} animationType="slide" presentationStyle="pageSheet" onRequestClose={() => setOuter(false)}>
        <View style={styles.modal}>
          <Text style={styles.title}>RN Modal</Text>
          <SheetButton label="in modal" testID="sheet-modal" />
          <Pressable testID="open-nested" onPress={() => setInner(true)} style={styles.button}>
            <Text style={styles.buttonText}>Open modal over modal</Text>
          </Pressable>
          <Pressable testID="close-modal" onPress={() => setOuter(false)} style={[styles.button, styles.secondary]}>
            <Text style={styles.buttonText}>Close</Text>
          </Pressable>
          <Modal visible={inner} animationType="slide" presentationStyle="fullScreen" onRequestClose={() => setInner(false)}>
            <View style={styles.modal}>
              <Text style={styles.title}>Modal over modal</Text>
              <SheetButton label="nested modal" testID="sheet-nested" />
              <SheetButton label="nested, host on root (0.1.1)" testID="sheet-nested-root" attachToRoot />
              <Pressable testID="close-nested" onPress={() => setInner(false)} style={[styles.button, styles.secondary]}>
                <Text style={styles.buttonText}>Close</Text>
              </Pressable>
            </View>
          </Modal>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  modal: { flex: 1, padding: 24, paddingTop: 80, gap: 12, backgroundColor: "#fff" },
  title: { fontSize: 18, fontWeight: "700" },
  button: { backgroundColor: "#36c", paddingVertical: 10, paddingHorizontal: 14, borderRadius: 8 },
  secondary: { backgroundColor: "#888" },
  buttonText: { color: "white", fontWeight: "600" },
  detail: { fontFamily: "Menlo", fontSize: 11, color: "#333" },
});
