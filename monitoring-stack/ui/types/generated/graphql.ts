import type { GraphQLResolveInfo, GraphQLScalarType, GraphQLScalarTypeConfig } from 'graphql';
export type Maybe<T> = T | null;
export type InputMaybe<T> = Maybe<T>;
export type Exact<T extends { [key: string]: unknown }> = { [K in keyof T]: T[K] };
export type MakeOptional<T, K extends keyof T> = Omit<T, K> & { [SubKey in K]?: Maybe<T[SubKey]> };
export type MakeMaybe<T, K extends keyof T> = Omit<T, K> & { [SubKey in K]: Maybe<T[SubKey]> };
export type MakeEmpty<T extends { [key: string]: unknown }, K extends keyof T> = { [_ in K]?: never };
export type Incremental<T> = T | { [P in keyof T]?: P extends ' $fragmentName' | '__typename' ? T[P] : never };
export type RequireFields<T, K extends keyof T> = Omit<T, K> & { [P in K]-?: NonNullable<T[P]> };
/** All built-in and custom scalars, mapped to their actual values */
export type Scalars = {
  ID: { input: string; output: string; }
  String: { input: string; output: string; }
  Boolean: { input: boolean; output: boolean; }
  Int: { input: number; output: number; }
  Float: { input: number; output: number; }
  /** A scalar that can represent any JSON Object value. */
  JSONObject: { input: any; output: any; }
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
  notificationSettings?: InputMaybe<Array<NotificationSettingInput>>;
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
  reports: Array<Report>;
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

export type WithIndex<TObject> = TObject & Record<string, any>;
export type ResolversObject<TObject> = WithIndex<TObject>;

export type ResolverTypeWrapper<T> = Promise<T> | T;


export type ResolverWithResolve<TResult, TParent, TContext, TArgs> = {
  resolve: ResolverFn<TResult, TParent, TContext, TArgs>;
};
export type Resolver<TResult, TParent = Record<PropertyKey, never>, TContext = Record<PropertyKey, never>, TArgs = Record<PropertyKey, never>> = ResolverFn<TResult, TParent, TContext, TArgs> | ResolverWithResolve<TResult, TParent, TContext, TArgs>;

export type ResolverFn<TResult, TParent, TContext, TArgs> = (
  parent: TParent,
  args: TArgs,
  context: TContext,
  info: GraphQLResolveInfo
) => Promise<TResult> | TResult;

export type SubscriptionSubscribeFn<TResult, TParent, TContext, TArgs> = (
  parent: TParent,
  args: TArgs,
  context: TContext,
  info: GraphQLResolveInfo
) => AsyncIterable<TResult> | Promise<AsyncIterable<TResult>>;

export type SubscriptionResolveFn<TResult, TParent, TContext, TArgs> = (
  parent: TParent,
  args: TArgs,
  context: TContext,
  info: GraphQLResolveInfo
) => TResult | Promise<TResult>;

export interface SubscriptionSubscriberObject<TResult, TKey extends string, TParent, TContext, TArgs> {
  subscribe: SubscriptionSubscribeFn<{ [key in TKey]: TResult }, TParent, TContext, TArgs>;
  resolve?: SubscriptionResolveFn<TResult, { [key in TKey]: TResult }, TContext, TArgs>;
}

export interface SubscriptionResolverObject<TResult, TParent, TContext, TArgs> {
  subscribe: SubscriptionSubscribeFn<any, TParent, TContext, TArgs>;
  resolve: SubscriptionResolveFn<TResult, any, TContext, TArgs>;
}

export type SubscriptionObject<TResult, TKey extends string, TParent, TContext, TArgs> =
  | SubscriptionSubscriberObject<TResult, TKey, TParent, TContext, TArgs>
  | SubscriptionResolverObject<TResult, TParent, TContext, TArgs>;

export type SubscriptionResolver<TResult, TKey extends string, TParent = Record<PropertyKey, never>, TContext = Record<PropertyKey, never>, TArgs = Record<PropertyKey, never>> =
  | ((...args: any[]) => SubscriptionObject<TResult, TKey, TParent, TContext, TArgs>)
  | SubscriptionObject<TResult, TKey, TParent, TContext, TArgs>;

export type TypeResolveFn<TTypes, TParent = Record<PropertyKey, never>, TContext = Record<PropertyKey, never>> = (
  parent: TParent,
  context: TContext,
  info: GraphQLResolveInfo
) => Maybe<TTypes> | Promise<Maybe<TTypes>>;

export type IsTypeOfResolverFn<T = Record<PropertyKey, never>, TContext = Record<PropertyKey, never>> = (obj: T, context: TContext, info: GraphQLResolveInfo) => boolean | Promise<boolean>;

export type NextResolverFn<T> = () => Promise<T>;

export type DirectiveResolverFn<TResult = Record<PropertyKey, never>, TParent = Record<PropertyKey, never>, TContext = Record<PropertyKey, never>, TArgs = Record<PropertyKey, never>> = (
  next: NextResolverFn<TResult>,
  parent: TParent,
  args: TArgs,
  context: TContext,
  info: GraphQLResolveInfo
) => TResult | Promise<TResult>;





/** Mapping between all available schema types and the resolvers types */
export type ResolversTypes = ResolversObject<{
  Boolean: ResolverTypeWrapper<Scalars['Boolean']['output']>;
  Int: ResolverTypeWrapper<Scalars['Int']['output']>;
  JSONObject: ResolverTypeWrapper<Scalars['JSONObject']['output']>;
  LoginPayload: ResolverTypeWrapper<LoginPayload>;
  Mutation: ResolverTypeWrapper<Record<PropertyKey, never>>;
  NotificationSettingInput: NotificationSettingInput;
  Query: ResolverTypeWrapper<Record<PropertyKey, never>>;
  Report: ResolverTypeWrapper<Report>;
  String: ResolverTypeWrapper<Scalars['String']['output']>;
  SubscribePayload: ResolverTypeWrapper<SubscribePayload>;
  SubscriptionInput: SubscriptionInput;
  SubscriptionKeysInput: SubscriptionKeysInput;
  UserProfile: ResolverTypeWrapper<UserProfile>;
}>;

/** Mapping between all available schema types and the resolvers parents */
export type ResolversParentTypes = ResolversObject<{
  Boolean: Scalars['Boolean']['output'];
  Int: Scalars['Int']['output'];
  JSONObject: Scalars['JSONObject']['output'];
  LoginPayload: LoginPayload;
  Mutation: Record<PropertyKey, never>;
  NotificationSettingInput: NotificationSettingInput;
  Query: Record<PropertyKey, never>;
  Report: Report;
  String: Scalars['String']['output'];
  SubscribePayload: SubscribePayload;
  SubscriptionInput: SubscriptionInput;
  SubscriptionKeysInput: SubscriptionKeysInput;
  UserProfile: UserProfile;
}>;

export interface JsonObjectScalarConfig extends GraphQLScalarTypeConfig<ResolversTypes['JSONObject'], any> {
  name: 'JSONObject';
}

export type LoginPayloadResolvers<ContextType = any, ParentType extends ResolversParentTypes['LoginPayload'] = ResolversParentTypes['LoginPayload']> = ResolversObject<{
  expiresIn?: Resolver<ResolversTypes['Int'], ParentType, ContextType>;
  token?: Resolver<ResolversTypes['String'], ParentType, ContextType>;
}>;

export type MutationResolvers<ContextType = any, ParentType extends ResolversParentTypes['Mutation'] = ResolversParentTypes['Mutation']> = ResolversObject<{
  login?: Resolver<ResolversTypes['LoginPayload'], ParentType, ContextType, RequireFields<MutationLoginArgs, 'password' | 'username'>>;
  subscribe?: Resolver<ResolversTypes['SubscribePayload'], ParentType, ContextType, RequireFields<MutationSubscribeArgs, 'subscription'>>;
  updateUserProfile?: Resolver<ResolversTypes['UserProfile'], ParentType, ContextType, Partial<MutationUpdateUserProfileArgs>>;
}>;

export type QueryResolvers<ContextType = any, ParentType extends ResolversParentTypes['Query'] = ResolversParentTypes['Query']> = ResolversObject<{
  me?: Resolver<ResolversTypes['UserProfile'], ParentType, ContextType>;
  report?: Resolver<Maybe<ResolversTypes['Report']>, ParentType, ContextType, RequireFields<QueryReportArgs, 'reportId'>>;
  reports?: Resolver<Array<ResolversTypes['Report']>, ParentType, ContextType, RequireFields<QueryReportsArgs, 'userId'>>;
  vapidPublicKey?: Resolver<ResolversTypes['String'], ParentType, ContextType>;
}>;

export type ReportResolvers<ContextType = any, ParentType extends ResolversParentTypes['Report'] = ResolversParentTypes['Report']> = ResolversObject<{
  createdAtUnix?: Resolver<ResolversTypes['Int'], ParentType, ContextType>;
  reportBody?: Resolver<ResolversTypes['String'], ParentType, ContextType>;
  reportId?: Resolver<ResolversTypes['String'], ParentType, ContextType>;
  userId?: Resolver<ResolversTypes['String'], ParentType, ContextType>;
}>;

export type SubscribePayloadResolvers<ContextType = any, ParentType extends ResolversParentTypes['SubscribePayload'] = ResolversParentTypes['SubscribePayload']> = ResolversObject<{
  message?: Resolver<Maybe<ResolversTypes['String']>, ParentType, ContextType>;
  success?: Resolver<ResolversTypes['Boolean'], ParentType, ContextType>;
}>;

export type UserProfileResolvers<ContextType = any, ParentType extends ResolversParentTypes['UserProfile'] = ResolversParentTypes['UserProfile']> = ResolversObject<{
  displayName?: Resolver<ResolversTypes['String'], ParentType, ContextType>;
  id?: Resolver<ResolversTypes['String'], ParentType, ContextType>;
  notificationSettings?: Resolver<ResolversTypes['JSONObject'], ParentType, ContextType>;
}>;

export type Resolvers<ContextType = any> = ResolversObject<{
  JSONObject?: GraphQLScalarType;
  LoginPayload?: LoginPayloadResolvers<ContextType>;
  Mutation?: MutationResolvers<ContextType>;
  Query?: QueryResolvers<ContextType>;
  Report?: ReportResolvers<ContextType>;
  SubscribePayload?: SubscribePayloadResolvers<ContextType>;
  UserProfile?: UserProfileResolvers<ContextType>;
}>;

