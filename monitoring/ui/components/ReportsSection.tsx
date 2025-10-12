import { useRouter } from 'expo-router';
import React, { useEffect, useState } from 'react';
import { FlatList, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
interface ReportsSectionProps {
  // Define any props if needed
}

interface Report {
  content: string;
  generatedAt: string; // ISO8601DateTime is a string
  reportId: string;
  reportName: string;
  reportType?: string; // Optional based on schema
  status: string;
}

const ReportsSection: React.FC<ReportsSectionProps> = () => {
  const router = useRouter();
  const [reports, setReports] = useState<Report[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchReports = async () => {
      try {
        const graphqlEndpoint = process.env.EXPO_PUBLIC_GRAPHQL_ENDPOINT || 'http://192.168.5.62:30005/graphql';
        const response = await fetch(graphqlEndpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            query: `
              query {
                reports {
                  content
                  generatedAt
                  reportId
                  reportName
                  reportType
                  status
                }
              }
            `,
          }),
        });

        const result = await response.json();

        if (result.errors) {
          console.error('GraphQL errors:', result.errors);
          setError(result.errors[0].message);
        } else if (result.data && result.data.reports) {
          setReports(result.data.reports);
        }
      } catch (err: any) {
        console.error('Error fetching reports:', err);
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };

    fetchReports();
  }, []);

  if (loading) {
    return <Text>Loading reports...</Text>;
  }

  if (error) {
    return <Text style={styles.errorText}>Error: {error}</Text>;
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Reports</Text>
      {reports.length === 0 ? (
        <Text>No reports found.</Text>
      ) : (
        <FlatList
          data={reports}
          keyExtractor={(item) => item.reportId}
          renderItem={({ item }) => (
            <TouchableOpacity
              style={styles.reportItem}
              onPress={() => router.push(`/reports/${item.reportId}`)}
            >
              <Text style={styles.reportName}>{item.reportName}</Text>
              <Text>ID: {item.reportId}</Text>
              <Text>Type: {item.reportType}</Text>
              <Text>Generated At: {item.generatedAt}</Text>
              <Text>Status: {item.status}</Text>
            </TouchableOpacity>
          )}
        />
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    marginTop: 20,
    paddingHorizontal: 16,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 10,
  },
  reportItem: {
    backgroundColor: '#fff',
    padding: 15,
    borderRadius: 8,
    marginBottom: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 1.41,
    elevation: 2,
  },
  reportName: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 5,
  },
  errorText: {
    color: 'red',
    marginTop: 20,
    paddingHorizontal: 16,
  },
});

export default ReportsSection;
