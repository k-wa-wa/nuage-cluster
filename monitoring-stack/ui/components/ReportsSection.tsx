import { IconSymbol } from "@/components/ui/icon-symbol"; // Import IconSymbol
import { graphqlEndpoint } from "@/constants/config";
import { useRouter } from "expo-router";
import React, { useEffect, useState } from "react";
import {
  Dimensions,
  FlatList,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";
interface ReportsSectionProps {
  // Define any props if needed
}

interface Report {
  reportId: string
  reportBody: string
  userId: string
  createdAtUnix: number
}

const ReportsSection: React.FC<ReportsSectionProps> = () => {
  const router = useRouter()
  const [reports, setReports] = useState<Report[]>([])
  const [loading, setLoading] = useState<boolean>(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
        const fetchReports = async () => {
      try {
        const response = await fetch(graphqlEndpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            query: `
              query Reports($userId: String!) {
                reports(userId: $userId) {
                  reportId
                  reportBody
                  userId
                  createdAtUnix
                }
              }
            `,
            variables: {
              userId: "", // 空文字を渡す
            },
          }),
        })

        const result = await response.json()

        if (result.errors) {
          console.error("GraphQL errors (reports query):", result.errors)
          setError(result.errors[0].message)
        } else if (result.data && result.data.reports) {
          setReports(result.data.reports)
        }
      } catch (err: any) {
        console.error("Error fetching reports:", err)
        setError(err.message)
      } finally {
        setLoading(false)
      }
    }

    fetchReports()
  }, [])

  if (loading) {
    return <Text>Loading reports...</Text>
  }

  if (error) {
    return <Text style={styles.errorText}>Error: {error}</Text>
  }

  const formatRelativeTime = (timestamp: number) => {
    const seconds = Math.floor((new Date().getTime() - new Date(timestamp * 1000).getTime()) / 1000);

    let interval = seconds / 31536000;
    if (interval > 1) return Math.floor(interval) + " years ago";
    interval = seconds / 2592000;
    if (interval > 1) return Math.floor(interval) + " months ago";
    interval = seconds / 86400;
    if (interval > 1) return Math.floor(interval) + " days ago";
    interval = seconds / 3600;
    if (interval > 1) return Math.floor(interval) + " hours ago";
    interval = seconds / 60;
    if (interval > 1) return Math.floor(interval) + " minutes ago";
    return Math.floor(seconds) + " seconds ago";
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Reports</Text>
      {reports.length === 0 ? (
        <Text>No reports found.</Text>
      ) : (
        <FlatList
          data={reports}
          keyExtractor={(item) => item.reportId}
          numColumns={isMobile ? 1 : 2} // 1 column for mobile, 2 for tablet/PC
          columnWrapperStyle={!isMobile && styles.columnWrapper} // Apply wrapper style for 2 columns
          renderItem={({ item }) => (
            <TouchableOpacity
              style={styles.reportItem}
              onPress={() => router.push(`/reports/${item.reportId}`)}
            >
              <Text style={styles.reportName}>{item.reportId}</Text>
              <View style={styles.userInfo}>
                <IconSymbol name="person.fill" size={16} color="#333" />
                <Text style={styles.userIdText}>{item.userId}</Text>
              </View>
              <Text style={styles.createdAtText}>{formatRelativeTime(item.createdAtUnix)}</Text>
            </TouchableOpacity>
          )}
        />
      )}
    </View>
  )
}

const { width } = Dimensions.get("window")

const isMobile = width < 768
const isTablet = width >= 768 && width < 1024
const isDesktop = width >= 1024

const styles = StyleSheet.create({
  container: {
    flex: 1, // Ensure the container takes up available space
    marginTop: isMobile ? 10 : isTablet ? 20 : 30,
    paddingHorizontal: isMobile ? 16 : isTablet ? 32 : 64,
  },
  title: {
    fontSize: isMobile ? 20 : isTablet ? 28 : 36,
    fontWeight: "bold",
    marginBottom: 10,
  },
  columnWrapper: {
    justifyContent: "space-between",
    marginBottom: 10, // Add margin between rows in a multi-column layout
  },
  reportItem: {
    backgroundColor: "#fff",
    padding: isMobile ? 10 : isTablet ? 15 : 20,
    borderRadius: 8,
    flex: isMobile ? undefined : 1, // Take full width on mobile, flexible width in multi-column
    marginHorizontal: isMobile ? 0 : 5, // Add horizontal margin for spacing between columns
    marginBottom: 10, // Always add bottom margin for spacing between items/rows
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 1.41,
    elevation: 2,
  },
  reportName: {
    fontSize: isMobile ? 16 : isTablet ? 18 : 20,
    fontWeight: "bold",
    marginBottom: 5,
  },
  userInfo: {
    flexDirection: "row",
    alignItems: "center",
    marginBottom: 5,
  },
  userIdText: {
    marginLeft: 5,
    fontSize: isMobile ? 12 : isTablet ? 14 : 16,
  },
  createdAtText: {
    fontSize: isMobile ? 12 : isTablet ? 14 : 16,
    color: "#666",
  },
  errorText: {
    color: "red",
    marginTop: isMobile ? 20 : isTablet ? 25 : 30,
    paddingHorizontal: isMobile ? 16 : isTablet ? 32 : 64,
  },
})

export default ReportsSection
