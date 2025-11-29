import { GraphQLClient } from 'graphql-request'; // RequestOptionsを削除
import gql from 'graphql-tag';
export type Maybe<T> = T | null;
export type InputMaybe<T> = Maybe<T>;
export type Exact<T extends { [key: string]: unknown }> = { [K in keyof T]: T[K] };
export type MakeOptional<T, K extends keyof T> = Omit<T, K> & { [SubKey in K]?: Maybe<T[SubKey]> };
export type MakeMaybe<T, K extends keyof T> = Omit<T, K> & { [SubKey in K]: Maybe<T[SubKey]> };
export type MakeEmpty<T extends { [key: string]: unknown }, K extends keyof T> = { [_ in K]?: never };
export type Incremental<T> = T | { [P in keyof T]?: P extends ' $fragmentName' | '__typename' ? T[P] : never };
type GraphQLClientRequestHeaders = HeadersInit; // RequestOptions['requestHeaders']をHeadersInitに変更
/** All built-in and custom scalars, mapped to their actual values */
export type Scalars = {
  ID: { input: string; output: string; }
  String: { input: string; output: string; }
  Boolean: { input: boolean; output: boolean; }
  Int: { input: number; output: number; }
  Float: { input: number; output: number; }
  /** A scalar that can represent any JSON Object value. */
  JSONObject: { input: Record<string, any>; output: Record<string, any>; }
};

export type LoginPayload = {
  __typename?: 'LoginPayload';
  expiresIn: Scalars['Int']['output'];
  token: Scalars['String']['output'];
};

export type Mutation = {
  __typename?: 'Mutation';
  /** ユーザー認証を行い、JWTを返します。 */
  login: LoginPayload;
  /** プッシュ通知の購読情報を登録します。 */
  subscribe: SubscribePayload;
  /** ユーザープロファイルを更新します。 */
  updateUserProfile: UserProfile;
};


export type MutationLoginArgs = {
  password: Scalars['String']['input'];
  username: Scalars['String']['input'];
};


export type MutationSubscribeArgs = {
  subscription: SubscriptionInput;
};


export type MutationUpdateUserProfileArgs = {
  displayName?: InputMaybe<Scalars['String']['input']>;
  notificationSettings?: InputMaybe<NotificationSettingInput[]>;
};

export type NotificationSettingInput = {
  key: Scalars['String']['input'];
  value: Scalars['String']['input'];
};

export type Query = {
  __typename?: 'Query';
  /** 認証済みのユーザープロファイルを取得します。 */
  me: UserProfile;
  /** 特定のレポートを取得します。 */
  report?: Maybe<Report>;
  /** レポート一覧を取得します。 */
  reports: Report[];
  /** VAPID公開鍵を取得します。 */
  vapidPublicKey: Scalars['String']['output'];
};


export type QueryReportArgs = {
  reportId: Scalars['String']['input'];
};


export type QueryReportsArgs = {
  pageSize?: InputMaybe<Scalars['Int']['input']>;
  pageToken?: InputMaybe<Scalars['String']['input']>;
  userId: Scalars['String']['input'];
};

export type Report = {
  __typename?: 'Report';
  createdAtUnix: Scalars['Int']['output'];
  reportBody: Scalars['String']['output'];
  reportId: Scalars['String']['output'];
  userId: Scalars['String']['output'];
};

export type SubscribePayload = {
  __typename?: 'SubscribePayload';
  message?: Maybe<Scalars['String']['output']>;
  success: Scalars['Boolean']['output'];
};

export type SubscriptionInput = {
  endpoint: Scalars['String']['input'];
  expirationTime?: InputMaybe<Scalars['String']['input']>;
  keys: SubscriptionKeysInput;
};

export type SubscriptionKeysInput = {
  auth: Scalars['String']['input'];
  p256dh: Scalars['String']['input'];
};

export type UserProfile = {
  __typename?: 'UserProfile';
  displayName: Scalars['String']['output'];
  id: Scalars['String']['output'];
  notificationSettings: Scalars['JSONObject']['output'];
};

export type VapidPublicKeyQueryVariables = Exact<{ [key: string]: never; }>;


export type VapidPublicKeyQuery = { __typename?: 'Query', vapidPublicKey: string };

export type SubscribeMutationVariables = Exact<{
  subscription: SubscriptionInput;
}>;


export type SubscribeMutation = { __typename?: 'Mutation', subscribe: { __typename?: 'SubscribePayload', success: boolean, message?: string | null } };

export type LoginMutationVariables = Exact<{
  username: Scalars['String']['input'];
  password: Scalars['String']['input'];
}>;


export type LoginMutation = { __typename?: 'Mutation', login: { __typename?: 'LoginPayload', token: string, expiresIn: number } };


export const VapidPublicKeyDocument = gql`
    query VapidPublicKey {
  vapidPublicKey
}
    `;
export const SubscribeDocument = gql`
    mutation Subscribe($subscription: SubscriptionInput!) {
  subscribe(subscription: $subscription) {
    success
    message
  }
}
    `;
export const LoginDocument = gql`
    mutation Login($username: String!, $password: String!) {
  login(username: $username, password: $password) {
    token
    expiresIn
  }
}
    `;

export type SdkFunctionWrapper = <T>(action: (requestHeaders?:Record<string, string>) => Promise<T>, operationName: string, operationType?: string, variables?: any) => Promise<T>;


const defaultWrapper: SdkFunctionWrapper = (action, _operationName, _operationType, _variables) => action();

export function getSdk(client: GraphQLClient, withWrapper: SdkFunctionWrapper = defaultWrapper) {
  return {
    VapidPublicKey(variables?: VapidPublicKeyQueryVariables, requestHeaders?: GraphQLClientRequestHeaders, signal?: RequestInit['signal']): Promise<VapidPublicKeyQuery> {
      return withWrapper((wrappedRequestHeaders) => client.request<VapidPublicKeyQuery>({ document: VapidPublicKeyDocument, variables, requestHeaders: { ...requestHeaders, ...wrappedRequestHeaders }, signal }), 'VapidPublicKey', 'query', variables);
    },
    Subscribe(variables: SubscribeMutationVariables, requestHeaders?: GraphQLClientRequestHeaders, signal?: RequestInit['signal']): Promise<SubscribeMutation> {
      return withWrapper((wrappedRequestHeaders) => client.request<SubscribeMutation>({ document: SubscribeDocument, variables, requestHeaders: { ...requestHeaders, ...wrappedRequestHeaders }, signal }), 'Subscribe', 'mutation', variables);
    },
    Login(variables: LoginMutationVariables, requestHeaders?: GraphQLClientRequestHeaders, signal?: RequestInit['signal']): Promise<LoginMutation> {
      return withWrapper((wrappedRequestHeaders) => client.request<LoginMutation>({ document: LoginDocument, variables, requestHeaders: { ...requestHeaders, ...wrappedRequestHeaders }, signal }), 'Login', 'mutation', variables);
    }
  };
}
export type Sdk = ReturnType<typeof getSdk>;
