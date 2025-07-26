import { FontAwesome } from "@expo/vector-icons";
import { Tabs } from "expo-router";

export default function RootLayout() {
  return (
    <Tabs
      screenOptions={{
        tabBarStyle: {
          backgroundColor: "#1E1E1E", // Dark background for tab bar
          borderTopColor: "#333333", // Darker border
        },
        tabBarActiveTintColor: "#F0F0F0", // Active icon/text color
        tabBarInactiveTintColor: "#B0B0B0", // Inactive icon/text color
        headerStyle: {
          backgroundColor: "#1E1E1E", // Dark background for header
        },
        headerTintColor: "#F0F0F0", // Header title color
        headerTitleStyle: {
          fontWeight: "bold",
        },
      }}
    >
      <Tabs.Screen
        name="screens/HomeScreen"
        options={{
          title: "Home",
          headerTitle: "Nuage Dashboard",
          tabBarIcon: ({ color }) => (
            <FontAwesome size={28} name="home" color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="screens/SettingsScreen"
        options={{
          title: "Settings",
          tabBarIcon: ({ color }) => (
            <FontAwesome size={28} name="cog" color={color} />
          ),
        }}
      />
    </Tabs>
  );
}
