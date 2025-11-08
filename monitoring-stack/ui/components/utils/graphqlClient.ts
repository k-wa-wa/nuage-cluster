import { graphqlEndpoint } from '@/constants/config';
import { getSdk } from '@/types/graphql';
import { GraphQLClient } from 'graphql-request';

const client = new GraphQLClient(graphqlEndpoint);
const sdk = getSdk(client);

export { sdk };
