import React from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import Card from "../../components/Card";

export default function HomeScreen() {
  return (
    <View style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollViewContent}>
        <Text style={styles.sectionTitle}>Operation</Text>
        <View style={styles.cardRow}>
          <Card
            title="Proxmox"
            description="aaaaa"
            buttonText="Visit"
            url="https://www.proxmox.com/"
          />
          <Card
            title="Grafana"
            description="bbbbb"
            buttonText="Dashboards"
            url="https://grafana.com/"
          />
          <Card
            title="Argo Workflow"
            description="ccccc"
            buttonText="Visit"
            url="https://argoproj.github.io/argo-workflows/"
          />
        </View>

        <Text style={styles.sectionTitle}>Pechka</Text>
        <View style={styles.cardRow}>
          <Card
            title="File server"
            description="aaa"
            buttonText="Visit"
            url="https://www.example.com/fileserver"
          />
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#1A1A1A", // Slightly lighter dark background
  },
  scrollViewContent: {
    padding: 20,
  },
  sectionTitle: {
    fontSize: 22,
    fontWeight: "bold",
    color: "#F0F0F0", // Slightly brighter text
    marginTop: 20,
    marginBottom: 10,
  },
  cardRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    justifyContent: "flex-start",
    marginHorizontal: -10, // Counteract card margin
  },
});
