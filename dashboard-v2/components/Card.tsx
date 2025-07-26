import { FontAwesome } from "@expo/vector-icons";
import React from "react";
import { Linking, StyleSheet, Text, TouchableOpacity, View } from "react-native";

interface CardProps {
  title: string;
  description: string;
  buttonText: string;
  url: string;
}

const Card: React.FC<CardProps> = ({ title, description, buttonText, url }) => {
  const handlePress = () => {
    Linking.openURL(url).catch((err) =>
      console.error("Failed to open URL:", err)
    );
  };

  return (
    <View style={styles.card}>
      <Text style={styles.cardTitle}>{title}</Text>
      <Text style={styles.cardDescription}>{description}</Text>
      <TouchableOpacity style={styles.button} onPress={handlePress}>
        <Text style={styles.buttonText}>{buttonText}</Text>
        <FontAwesome name="external-link" size={14} color="#E0E0E0" style={styles.icon} />
      </TouchableOpacity>
    </View>
  );
};

const styles = StyleSheet.create({
  card: {
    backgroundColor: "#2C2C2C", // Adjusted card background
    borderRadius: 10, // Slightly more rounded corners
    padding: 25, // Increased padding
    margin: 10,
    width: 180, // Increased width for cards
    height: 160, // Added height for cards
    shadowColor: "#000",
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
    justifyContent: "space-between",
  },
  cardTitle: {
    fontSize: 18,
    fontWeight: "bold",
    color: "#F0F0F0", // Adjusted text color
    marginBottom: 8, // Increased margin
  },
  cardDescription: {
    fontSize: 12,
    color: "#D0D0D0", // Adjusted description color
    marginBottom: 20, // Increased margin
  },
  button: {
    flexDirection: "row",
    backgroundColor: "#3A3A3A", // Adjusted button background
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 5,
    alignItems: "center",
    justifyContent: "center",
  },
  buttonText: {
    color: "#F0F0F0", // Adjusted button text color
    fontSize: 15, // Slightly larger font
    fontWeight: "bold",
    marginRight: 8, // Increased margin
  },
  icon: {
    marginLeft: 8, // Increased margin
  },
});

export default Card;
