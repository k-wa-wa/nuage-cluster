import { IconSymbol } from '@/components/ui/icon-symbol'; // Import IconSymbol
import { graphqlEndpoint } from '@/constants/config';
import { Stack, useLocalSearchParams } from 'expo-router';
import React, { useEffect, useState } from 'react';
import { ActivityIndicator, ScrollView, StyleSheet, Text, View } from 'react-native';
import Markdown from 'react-native-markdown-display';

interface Report {
  reportId: string;
  reportBody: string;
  userId: string;
  createdAtUnix: number;
}

const ReportDetailPage: React.FC = () => {
  const { id } = useLocalSearchParams();
  const [report, setReport] = useState<Report | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) {
      setError("Report ID is missing.");
      setLoading(false);
      return;
    }

    const fetchReport = async () => {
      try {
        const response = await fetch(graphqlEndpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            query: `
              query Report($reportId: String!) {
                report(reportId: $reportId) {
                  reportId
                  reportBody
                  userId
                  createdAtUnix
                }
              }
            `,
            variables: {
              reportId: id,
            },
          }),
        });

        const result = await response.json();

        if (result.errors) {
          console.error('GraphQL errors:', result.errors);
          setError(result.errors[0].message);
        } else if (result.data && result.data.report) {
          setReport(result.data.report);
        } else {
          setError("Report not found.");
        }
      } catch (err: any) {
        console.error('Error fetching report:', err);
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };

    fetchReport();
  }, [id]);

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color="#0000ff" />
        <Text>Loading report...</Text>
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.centered}>
        <Text style={styles.errorText}>Error: {error}</Text>
      </View>
    );
  }

  if (!report) {
    return (
      <View style={styles.centered}>
        <Text>No report data available.</Text>
      </View>
    );
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
    <ScrollView style={styles.container}>
      <Stack.Screen options={{ title: report.reportId }} />
      <Text style={styles.title}>{report.reportId}</Text>
      <View style={styles.userInfo}>
        <IconSymbol name="person.fill" size={16} color="#333" />
        <Text style={styles.userIdText}>{report.userId}</Text>
      </View>
      <Text style={styles.createdAtText}>{formatRelativeTime(report.createdAtUnix)}</Text>
      <View style={styles.contentContainer}>
        <Markdown style={markdownStyles}>{report.reportBody}</Markdown>
      </View>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
    backgroundColor: '#f8f8f8',
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  title: {
    fontSize: 26,
    fontWeight: 'bold',
    marginBottom: 10,
    color: '#333',
  },
  userInfo: {
    flexDirection: "row",
    alignItems: "center",
    marginBottom: 5,
  },
  userIdText: {
    marginLeft: 5,
    fontSize: 16,
    color: '#666',
  },
  createdAtText: {
    fontSize: 16,
    color: '#666',
    marginBottom: 5,
  },
  contentContainer: {
    marginTop: 20,
    padding: 15,
    backgroundColor: '#fff',
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 3,
  },
  content: {
    fontSize: 16,
    lineHeight: 24,
    color: '#333',
  },
  errorText: {
    color: 'red',
    fontSize: 18,
  },
});

const markdownStyles = StyleSheet.create({
  body: {
    fontSize: 16,
    lineHeight: 24,
    color: '#333',
  },
  heading1: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 10,
  },
  heading2: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  link: {
    color: '#007bff',
    textDecorationLine: 'underline',
  },
  list_item: {
    marginBottom: 5,
  },
  bullet_list_icon: {
    fontSize: 16,
    marginRight: 5,
  },
  ordered_list_icon: {
    fontSize: 16,
    marginRight: 5,
  },
  blockquote: {
    borderLeftColor: '#ccc',
    borderLeftWidth: 4,
    paddingLeft: 10,
    marginLeft: 5,
    fontStyle: 'italic',
  },
  code_inline: {
    backgroundColor: '#e0e0e0',
    padding: 2,
    borderRadius: 3,
    fontFamily: 'monospace',
  },
  code_block: {
    backgroundColor: '#e0e0e0',
    padding: 10,
    borderRadius: 5,
    fontFamily: 'monospace',
  },
});

export default ReportDetailPage;
