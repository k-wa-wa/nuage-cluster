import { graphqlEndpoint } from '@/constants/config';

export async function graphqlRequest<T>(query: string, variables?: Record<string, any>): Promise<T> {
  const response = await fetch(graphqlEndpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      query,
      variables,
    }),
  });

  const result = await response.json();

  if (result.errors) {
    throw new Error(result.errors.map((error: any) => error.message).join('\n'));
  }

  return result.data;
}
