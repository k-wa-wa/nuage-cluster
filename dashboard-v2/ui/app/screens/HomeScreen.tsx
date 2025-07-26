import React, { useEffect, useState } from "react";
import { ActivityIndicator, Alert, ScrollView, StyleSheet, Text, View } from "react-native";
import Card from "../../components/Card";

interface AppLink {
  name: string;
  url: string;
}

interface App {
  name: string;
  description: string;
  groupName: string;
  appLinks: AppLink[];
}

interface GroupedApps {
  [groupName: string]: App[];
}

export default function HomeScreen() {
  const [groupedApps, setGroupedApps] = useState<GroupedApps>({});
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchApps = async () => {
      try {
        // Assuming the BFF is running on localhost:3000. Adjust if your BFF is on a different port or host.
        const response = await fetch(`${process.env.EXPO_PUBLIC_API_URL || ""}/api/apps`);
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        const data: App[] = await response.json();

        const newGroupedApps: GroupedApps = data.reduce((acc, app) => {
          if (!acc[app.groupName]) {
            acc[app.groupName] = [];
          }
          acc[app.groupName].push(app);
          return acc;
        }, {} as GroupedApps);

        setGroupedApps(newGroupedApps);
      } catch (e: any) {
        console.error("Failed to fetch applications:", e);
        setError(e.message || "An unknown error occurred");
        Alert.alert("Error", "Failed to load applications. Please try again later.");
      } finally {
        setLoading(false);
      }
    };

    fetchApps();
  }, []);

  if (loading) {
    return (
      <View style={[styles.container, styles.centerContent]}>
        <ActivityIndicator size="large" color="#007AFF" />
        <Text style={styles.loadingText}>Loading applications...</Text>
      </View>
    );
  }

  if (error) {
    return (
      <View style={[styles.container, styles.centerContent]}>
        <Text style={styles.errorText}>Error: {error}</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollViewContent}>
        {Object.keys(groupedApps).map((groupName) => (
          <React.Fragment key={groupName}>
            <Text style={styles.sectionTitle}>{groupName}</Text>
            <View style={styles.cardRow}>
              {groupedApps[groupName].map((app) => (
                <Card
                  key={app.name} // Assuming app names are unique within a group
                  title={app.name}
                  description={app.description}
                  buttonText={app.appLinks.length > 0 ? app.appLinks[0].name : "Visit"} // Use first link name as button text
                  url={app.appLinks.length > 0 ? app.appLinks[0].url : "#"} // Use first link URL
                />
              ))}
            </View>
          </React.Fragment>
        ))}
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
  centerContent: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  loadingText: {
    color: "#F0F0F0",
    marginTop: 10,
    fontSize: 16,
  },
  errorText: {
    color: "#FF6347", // Tomato color for errors
    fontSize: 16,
    textAlign: "center",
    marginHorizontal: 20,
  },
});
