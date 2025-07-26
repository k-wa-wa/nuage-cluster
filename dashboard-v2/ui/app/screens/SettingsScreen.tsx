import { StyleSheet, Text, View } from "react-native";

export default function SettingsScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Settings Screen</Text>
      <Text style={styles.description}>
        This is a placeholder for the settings content.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    backgroundColor: "#1A1A1A", // Slightly lighter dark background
  },
  title: {
    fontSize: 24,
    fontWeight: "bold",
    color: "#F0F0F0", // Slightly brighter text
    marginBottom: 10,
  },
  description: {
    fontSize: 16,
    color: "#D0D0D0", // Adjusted light text
    textAlign: "center",
    paddingHorizontal: 20,
  },
});
