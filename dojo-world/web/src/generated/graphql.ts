import { useQuery, useInfiniteQuery, UseQueryOptions, UseInfiniteQueryOptions, QueryFunctionContext } from 'react-query';
import { useFetchData } from '@/hooks/fetcher';
export type Maybe<T> = T | null;
export type InputMaybe<T> = Maybe<T>;
export type Exact<T extends { [key: string]: unknown }> = { [K in keyof T]: T[K] };
export type MakeOptional<T, K extends keyof T> = Omit<T, K> & { [SubKey in K]?: Maybe<T[SubKey]> };
export type MakeMaybe<T, K extends keyof T> = Omit<T, K> & { [SubKey in K]: Maybe<T[SubKey]> };
/** All built-in and custom scalars, mapped to their actual values */
export type Scalars = {
  ID: string;
  String: string;
  Boolean: boolean;
  Int: number;
  Float: number;
  ByteArray: any;
  ContractAddress: any;
  Cursor: any;
  DateTime: any;
  Enum: any;
  bool: any;
  felt252: any;
  u32: any;
  u64: any;
};

export type ModelUnion = Dojo_World_DojoFren | Dojo_World_Quest | Dojo_World_QuestClaimed | Dojo_World_QuestCounter;

export enum OrderDirection {
  Asc = 'ASC',
  Desc = 'DESC'
}

export type World__Content = {
  __typename?: 'World__Content';
  coverUri?: Maybe<Scalars['String']>;
  description?: Maybe<Scalars['String']>;
  iconUri?: Maybe<Scalars['String']>;
  name?: Maybe<Scalars['String']>;
  socials?: Maybe<Array<Maybe<World__Social>>>;
  website?: Maybe<Scalars['String']>;
};

export type World__Entity = {
  __typename?: 'World__Entity';
  createdAt?: Maybe<Scalars['DateTime']>;
  eventId?: Maybe<Scalars['String']>;
  executedAt?: Maybe<Scalars['DateTime']>;
  id?: Maybe<Scalars['ID']>;
  keys?: Maybe<Array<Maybe<Scalars['String']>>>;
  models?: Maybe<Array<Maybe<ModelUnion>>>;
  updatedAt?: Maybe<Scalars['DateTime']>;
};

export type World__EntityConnection = {
  __typename?: 'World__EntityConnection';
  edges?: Maybe<Array<Maybe<World__EntityEdge>>>;
  pageInfo: World__PageInfo;
  totalCount: Scalars['Int'];
};

export type World__EntityEdge = {
  __typename?: 'World__EntityEdge';
  cursor?: Maybe<Scalars['Cursor']>;
  node?: Maybe<World__Entity>;
};

export type World__Event = {
  __typename?: 'World__Event';
  createdAt?: Maybe<Scalars['DateTime']>;
  data?: Maybe<Array<Maybe<Scalars['String']>>>;
  executedAt?: Maybe<Scalars['DateTime']>;
  id?: Maybe<Scalars['ID']>;
  keys?: Maybe<Array<Maybe<Scalars['String']>>>;
  transactionHash?: Maybe<Scalars['String']>;
};

export type World__EventConnection = {
  __typename?: 'World__EventConnection';
  edges?: Maybe<Array<Maybe<World__EventEdge>>>;
  pageInfo: World__PageInfo;
  totalCount: Scalars['Int'];
};

export type World__EventEdge = {
  __typename?: 'World__EventEdge';
  cursor?: Maybe<Scalars['Cursor']>;
  node?: Maybe<World__Event>;
};

export type World__EventMessage = {
  __typename?: 'World__EventMessage';
  createdAt?: Maybe<Scalars['DateTime']>;
  eventId?: Maybe<Scalars['String']>;
  executedAt?: Maybe<Scalars['DateTime']>;
  id?: Maybe<Scalars['ID']>;
  keys?: Maybe<Array<Maybe<Scalars['String']>>>;
  models?: Maybe<Array<Maybe<ModelUnion>>>;
  updatedAt?: Maybe<Scalars['DateTime']>;
};

export type World__EventMessageConnection = {
  __typename?: 'World__EventMessageConnection';
  edges?: Maybe<Array<Maybe<World__EventMessageEdge>>>;
  pageInfo: World__PageInfo;
  totalCount: Scalars['Int'];
};

export type World__EventMessageEdge = {
  __typename?: 'World__EventMessageEdge';
  cursor?: Maybe<Scalars['Cursor']>;
  node?: Maybe<World__EventMessage>;
};

export type World__Metadata = {
  __typename?: 'World__Metadata';
  content?: Maybe<World__Content>;
  coverImg?: Maybe<Scalars['String']>;
  createdAt?: Maybe<Scalars['DateTime']>;
  executedAt?: Maybe<Scalars['DateTime']>;
  iconImg?: Maybe<Scalars['String']>;
  id?: Maybe<Scalars['ID']>;
  updatedAt?: Maybe<Scalars['DateTime']>;
  uri?: Maybe<Scalars['String']>;
  worldAddress: Scalars['String'];
};

export type World__MetadataConnection = {
  __typename?: 'World__MetadataConnection';
  edges?: Maybe<Array<Maybe<World__MetadataEdge>>>;
  pageInfo: World__PageInfo;
  totalCount: Scalars['Int'];
};

export type World__MetadataEdge = {
  __typename?: 'World__MetadataEdge';
  cursor?: Maybe<Scalars['Cursor']>;
  node?: Maybe<World__Metadata>;
};

export type World__Model = {
  __typename?: 'World__Model';
  classHash?: Maybe<Scalars['felt252']>;
  contractAddress?: Maybe<Scalars['felt252']>;
  createdAt?: Maybe<Scalars['DateTime']>;
  executedAt?: Maybe<Scalars['DateTime']>;
  id?: Maybe<Scalars['ID']>;
  name?: Maybe<Scalars['String']>;
  transactionHash?: Maybe<Scalars['felt252']>;
};

export type World__ModelConnection = {
  __typename?: 'World__ModelConnection';
  edges?: Maybe<Array<Maybe<World__ModelEdge>>>;
  pageInfo: World__PageInfo;
  totalCount: Scalars['Int'];
};

export type World__ModelEdge = {
  __typename?: 'World__ModelEdge';
  cursor?: Maybe<Scalars['Cursor']>;
  node?: Maybe<World__Model>;
};

export type World__ModelOrder = {
  direction: OrderDirection;
  field: World__ModelOrderField;
};

export enum World__ModelOrderField {
  ClassHash = 'CLASS_HASH',
  Name = 'NAME'
}

export type World__PageInfo = {
  __typename?: 'World__PageInfo';
  endCursor?: Maybe<Scalars['Cursor']>;
  hasNextPage?: Maybe<Scalars['Boolean']>;
  hasPreviousPage?: Maybe<Scalars['Boolean']>;
  startCursor?: Maybe<Scalars['Cursor']>;
};

export type World__Query = {
  __typename?: 'World__Query';
  dojoWorldDojoFrenModels?: Maybe<Dojo_World_DojoFrenConnection>;
  dojoWorldQuestClaimedModels?: Maybe<Dojo_World_QuestClaimedConnection>;
  dojoWorldQuestCounterModels?: Maybe<Dojo_World_QuestCounterConnection>;
  dojoWorldQuestModels?: Maybe<Dojo_World_QuestConnection>;
  entities?: Maybe<World__EntityConnection>;
  entity: World__Entity;
  eventMessage: World__EventMessage;
  eventMessages?: Maybe<World__EventMessageConnection>;
  events?: Maybe<World__EventConnection>;
  metadatas?: Maybe<World__MetadataConnection>;
  model: World__Model;
  models?: Maybe<World__ModelConnection>;
  transaction: World__Transaction;
  transactions?: Maybe<World__TransactionConnection>;
};


export type World__QueryDojoWorldDojoFrenModelsArgs = {
  after?: InputMaybe<Scalars['Cursor']>;
  before?: InputMaybe<Scalars['Cursor']>;
  first?: InputMaybe<Scalars['Int']>;
  last?: InputMaybe<Scalars['Int']>;
  limit?: InputMaybe<Scalars['Int']>;
  offset?: InputMaybe<Scalars['Int']>;
  order?: InputMaybe<Dojo_World_DojoFrenOrder>;
  where?: InputMaybe<Dojo_World_DojoFrenWhereInput>;
};


export type World__QueryDojoWorldQuestClaimedModelsArgs = {
  after?: InputMaybe<Scalars['Cursor']>;
  before?: InputMaybe<Scalars['Cursor']>;
  first?: InputMaybe<Scalars['Int']>;
  last?: InputMaybe<Scalars['Int']>;
  limit?: InputMaybe<Scalars['Int']>;
  offset?: InputMaybe<Scalars['Int']>;
  order?: InputMaybe<Dojo_World_QuestClaimedOrder>;
  where?: InputMaybe<Dojo_World_QuestClaimedWhereInput>;
};


export type World__QueryDojoWorldQuestCounterModelsArgs = {
  after?: InputMaybe<Scalars['Cursor']>;
  before?: InputMaybe<Scalars['Cursor']>;
  first?: InputMaybe<Scalars['Int']>;
  last?: InputMaybe<Scalars['Int']>;
  limit?: InputMaybe<Scalars['Int']>;
  offset?: InputMaybe<Scalars['Int']>;
  order?: InputMaybe<Dojo_World_QuestCounterOrder>;
  where?: InputMaybe<Dojo_World_QuestCounterWhereInput>;
};


export type World__QueryDojoWorldQuestModelsArgs = {
  after?: InputMaybe<Scalars['Cursor']>;
  before?: InputMaybe<Scalars['Cursor']>;
  first?: InputMaybe<Scalars['Int']>;
  last?: InputMaybe<Scalars['Int']>;
  limit?: InputMaybe<Scalars['Int']>;
  offset?: InputMaybe<Scalars['Int']>;
  order?: InputMaybe<Dojo_World_QuestOrder>;
  where?: InputMaybe<Dojo_World_QuestWhereInput>;
};


export type World__QueryEntitiesArgs = {
  after?: InputMaybe<Scalars['Cursor']>;
  before?: InputMaybe<Scalars['Cursor']>;
  first?: InputMaybe<Scalars['Int']>;
  keys?: InputMaybe<Array<InputMaybe<Scalars['String']>>>;
  last?: InputMaybe<Scalars['Int']>;
  limit?: InputMaybe<Scalars['Int']>;
  offset?: InputMaybe<Scalars['Int']>;
};


export type World__QueryEntityArgs = {
  id: Scalars['ID'];
};


export type World__QueryEventMessageArgs = {
  id: Scalars['ID'];
};


export type World__QueryEventMessagesArgs = {
  after?: InputMaybe<Scalars['Cursor']>;
  before?: InputMaybe<Scalars['Cursor']>;
  first?: InputMaybe<Scalars['Int']>;
  keys?: InputMaybe<Array<InputMaybe<Scalars['String']>>>;
  last?: InputMaybe<Scalars['Int']>;
  limit?: InputMaybe<Scalars['Int']>;
  offset?: InputMaybe<Scalars['Int']>;
};


export type World__QueryEventsArgs = {
  after?: InputMaybe<Scalars['Cursor']>;
  before?: InputMaybe<Scalars['Cursor']>;
  first?: InputMaybe<Scalars['Int']>;
  keys?: InputMaybe<Array<InputMaybe<Scalars['String']>>>;
  last?: InputMaybe<Scalars['Int']>;
  limit?: InputMaybe<Scalars['Int']>;
  offset?: InputMaybe<Scalars['Int']>;
};


export type World__QueryMetadatasArgs = {
  after?: InputMaybe<Scalars['Cursor']>;
  before?: InputMaybe<Scalars['Cursor']>;
  first?: InputMaybe<Scalars['Int']>;
  last?: InputMaybe<Scalars['Int']>;
  limit?: InputMaybe<Scalars['Int']>;
  offset?: InputMaybe<Scalars['Int']>;
};


export type World__QueryModelArgs = {
  id: Scalars['ID'];
};


export type World__QueryModelsArgs = {
  after?: InputMaybe<Scalars['Cursor']>;
  before?: InputMaybe<Scalars['Cursor']>;
  first?: InputMaybe<Scalars['Int']>;
  last?: InputMaybe<Scalars['Int']>;
  limit?: InputMaybe<Scalars['Int']>;
  offset?: InputMaybe<Scalars['Int']>;
  order?: InputMaybe<World__ModelOrder>;
};


export type World__QueryTransactionArgs = {
  transactionHash: Scalars['ID'];
};


export type World__QueryTransactionsArgs = {
  after?: InputMaybe<Scalars['Cursor']>;
  before?: InputMaybe<Scalars['Cursor']>;
  first?: InputMaybe<Scalars['Int']>;
  last?: InputMaybe<Scalars['Int']>;
  limit?: InputMaybe<Scalars['Int']>;
  offset?: InputMaybe<Scalars['Int']>;
};

export type World__Social = {
  __typename?: 'World__Social';
  name?: Maybe<Scalars['String']>;
  url?: Maybe<Scalars['String']>;
};

export type World__Subscription = {
  __typename?: 'World__Subscription';
  entityUpdated: World__Entity;
  eventEmitted: World__Event;
  eventMessageUpdated: World__EventMessage;
  modelRegistered: World__Model;
};


export type World__SubscriptionEntityUpdatedArgs = {
  id?: InputMaybe<Scalars['ID']>;
};


export type World__SubscriptionEventEmittedArgs = {
  keys?: InputMaybe<Array<InputMaybe<Scalars['String']>>>;
};


export type World__SubscriptionEventMessageUpdatedArgs = {
  id?: InputMaybe<Scalars['ID']>;
};


export type World__SubscriptionModelRegisteredArgs = {
  id?: InputMaybe<Scalars['ID']>;
};

export type World__Transaction = {
  __typename?: 'World__Transaction';
  calldata?: Maybe<Array<Maybe<Scalars['felt252']>>>;
  createdAt?: Maybe<Scalars['DateTime']>;
  executedAt?: Maybe<Scalars['DateTime']>;
  id?: Maybe<Scalars['ID']>;
  maxFee?: Maybe<Scalars['felt252']>;
  nonce?: Maybe<Scalars['felt252']>;
  senderAddress?: Maybe<Scalars['felt252']>;
  signature?: Maybe<Array<Maybe<Scalars['felt252']>>>;
  transactionHash?: Maybe<Scalars['felt252']>;
};

export type World__TransactionConnection = {
  __typename?: 'World__TransactionConnection';
  edges?: Maybe<Array<Maybe<World__TransactionEdge>>>;
  pageInfo: World__PageInfo;
  totalCount: Scalars['Int'];
};

export type World__TransactionEdge = {
  __typename?: 'World__TransactionEdge';
  cursor?: Maybe<Scalars['Cursor']>;
  node?: Maybe<World__Transaction>;
};

export type Dojo_World_DojoFren = {
  __typename?: 'dojo_world_DojoFren';
  entity?: Maybe<World__Entity>;
  kind?: Maybe<Scalars['Enum']>;
  player_id?: Maybe<Scalars['ContractAddress']>;
  spawned?: Maybe<Scalars['u32']>;
};

export type Dojo_World_DojoFrenConnection = {
  __typename?: 'dojo_world_DojoFrenConnection';
  edges?: Maybe<Array<Maybe<Dojo_World_DojoFrenEdge>>>;
  pageInfo: World__PageInfo;
  totalCount: Scalars['Int'];
};

export type Dojo_World_DojoFrenEdge = {
  __typename?: 'dojo_world_DojoFrenEdge';
  cursor?: Maybe<Scalars['Cursor']>;
  node?: Maybe<Dojo_World_DojoFren>;
};

export type Dojo_World_DojoFrenOrder = {
  direction: OrderDirection;
  field: Dojo_World_DojoFrenOrderField;
};

export enum Dojo_World_DojoFrenOrderField {
  Kind = 'KIND',
  PlayerId = 'PLAYER_ID',
  Spawned = 'SPAWNED'
}

export type Dojo_World_DojoFrenWhereInput = {
  kind?: InputMaybe<Scalars['Enum']>;
  player_id?: InputMaybe<Scalars['ContractAddress']>;
  player_idEQ?: InputMaybe<Scalars['ContractAddress']>;
  player_idGT?: InputMaybe<Scalars['ContractAddress']>;
  player_idGTE?: InputMaybe<Scalars['ContractAddress']>;
  player_idIN?: InputMaybe<Array<InputMaybe<Scalars['ContractAddress']>>>;
  player_idLIKE?: InputMaybe<Scalars['ContractAddress']>;
  player_idLT?: InputMaybe<Scalars['ContractAddress']>;
  player_idLTE?: InputMaybe<Scalars['ContractAddress']>;
  player_idNEQ?: InputMaybe<Scalars['ContractAddress']>;
  player_idNOTIN?: InputMaybe<Array<InputMaybe<Scalars['ContractAddress']>>>;
  player_idNOTLIKE?: InputMaybe<Scalars['ContractAddress']>;
  spawned?: InputMaybe<Scalars['u32']>;
  spawnedEQ?: InputMaybe<Scalars['u32']>;
  spawnedGT?: InputMaybe<Scalars['u32']>;
  spawnedGTE?: InputMaybe<Scalars['u32']>;
  spawnedIN?: InputMaybe<Array<InputMaybe<Scalars['u32']>>>;
  spawnedLIKE?: InputMaybe<Scalars['u32']>;
  spawnedLT?: InputMaybe<Scalars['u32']>;
  spawnedLTE?: InputMaybe<Scalars['u32']>;
  spawnedNEQ?: InputMaybe<Scalars['u32']>;
  spawnedNOTIN?: InputMaybe<Array<InputMaybe<Scalars['u32']>>>;
  spawnedNOTLIKE?: InputMaybe<Scalars['u32']>;
};

export type Dojo_World_Quest = {
  __typename?: 'dojo_world_Quest';
  availability?: Maybe<Dojo_World_Quest_QuestRules>;
  completion?: Maybe<Dojo_World_Quest_QuestRules>;
  desc?: Maybe<Scalars['ByteArray']>;
  entity?: Maybe<World__Entity>;
  external?: Maybe<Dojo_World_Quest_OptionContractAddress>;
  id?: Maybe<Scalars['felt252']>;
  image_uri?: Maybe<Dojo_World_Quest_OptionByteArray>;
  name?: Maybe<Scalars['ByteArray']>;
  quest_type?: Maybe<Scalars['Enum']>;
};

export type Dojo_World_QuestClaimed = {
  __typename?: 'dojo_world_QuestClaimed';
  claimed?: Maybe<Scalars['bool']>;
  entity?: Maybe<World__Entity>;
  player_id?: Maybe<Scalars['ContractAddress']>;
  quest_id?: Maybe<Scalars['felt252']>;
};

export type Dojo_World_QuestClaimedConnection = {
  __typename?: 'dojo_world_QuestClaimedConnection';
  edges?: Maybe<Array<Maybe<Dojo_World_QuestClaimedEdge>>>;
  pageInfo: World__PageInfo;
  totalCount: Scalars['Int'];
};

export type Dojo_World_QuestClaimedEdge = {
  __typename?: 'dojo_world_QuestClaimedEdge';
  cursor?: Maybe<Scalars['Cursor']>;
  node?: Maybe<Dojo_World_QuestClaimed>;
};

export type Dojo_World_QuestClaimedOrder = {
  direction: OrderDirection;
  field: Dojo_World_QuestClaimedOrderField;
};

export enum Dojo_World_QuestClaimedOrderField {
  Claimed = 'CLAIMED',
  PlayerId = 'PLAYER_ID',
  QuestId = 'QUEST_ID'
}

export type Dojo_World_QuestClaimedWhereInput = {
  claimed?: InputMaybe<Scalars['bool']>;
  player_id?: InputMaybe<Scalars['ContractAddress']>;
  player_idEQ?: InputMaybe<Scalars['ContractAddress']>;
  player_idGT?: InputMaybe<Scalars['ContractAddress']>;
  player_idGTE?: InputMaybe<Scalars['ContractAddress']>;
  player_idIN?: InputMaybe<Array<InputMaybe<Scalars['ContractAddress']>>>;
  player_idLIKE?: InputMaybe<Scalars['ContractAddress']>;
  player_idLT?: InputMaybe<Scalars['ContractAddress']>;
  player_idLTE?: InputMaybe<Scalars['ContractAddress']>;
  player_idNEQ?: InputMaybe<Scalars['ContractAddress']>;
  player_idNOTIN?: InputMaybe<Array<InputMaybe<Scalars['ContractAddress']>>>;
  player_idNOTLIKE?: InputMaybe<Scalars['ContractAddress']>;
  quest_id?: InputMaybe<Scalars['felt252']>;
  quest_idEQ?: InputMaybe<Scalars['felt252']>;
  quest_idGT?: InputMaybe<Scalars['felt252']>;
  quest_idGTE?: InputMaybe<Scalars['felt252']>;
  quest_idIN?: InputMaybe<Array<InputMaybe<Scalars['felt252']>>>;
  quest_idLIKE?: InputMaybe<Scalars['felt252']>;
  quest_idLT?: InputMaybe<Scalars['felt252']>;
  quest_idLTE?: InputMaybe<Scalars['felt252']>;
  quest_idNEQ?: InputMaybe<Scalars['felt252']>;
  quest_idNOTIN?: InputMaybe<Array<InputMaybe<Scalars['felt252']>>>;
  quest_idNOTLIKE?: InputMaybe<Scalars['felt252']>;
};

export type Dojo_World_QuestConnection = {
  __typename?: 'dojo_world_QuestConnection';
  edges?: Maybe<Array<Maybe<Dojo_World_QuestEdge>>>;
  pageInfo: World__PageInfo;
  totalCount: Scalars['Int'];
};

export type Dojo_World_QuestCounter = {
  __typename?: 'dojo_world_QuestCounter';
  count?: Maybe<Scalars['u64']>;
  entity?: Maybe<World__Entity>;
  player_id?: Maybe<Scalars['ContractAddress']>;
  quest_id?: Maybe<Scalars['felt252']>;
};

export type Dojo_World_QuestCounterConnection = {
  __typename?: 'dojo_world_QuestCounterConnection';
  edges?: Maybe<Array<Maybe<Dojo_World_QuestCounterEdge>>>;
  pageInfo: World__PageInfo;
  totalCount: Scalars['Int'];
};

export type Dojo_World_QuestCounterEdge = {
  __typename?: 'dojo_world_QuestCounterEdge';
  cursor?: Maybe<Scalars['Cursor']>;
  node?: Maybe<Dojo_World_QuestCounter>;
};

export type Dojo_World_QuestCounterOrder = {
  direction: OrderDirection;
  field: Dojo_World_QuestCounterOrderField;
};

export enum Dojo_World_QuestCounterOrderField {
  Count = 'COUNT',
  PlayerId = 'PLAYER_ID',
  QuestId = 'QUEST_ID'
}

export type Dojo_World_QuestCounterWhereInput = {
  count?: InputMaybe<Scalars['u64']>;
  countEQ?: InputMaybe<Scalars['u64']>;
  countGT?: InputMaybe<Scalars['u64']>;
  countGTE?: InputMaybe<Scalars['u64']>;
  countIN?: InputMaybe<Array<InputMaybe<Scalars['u64']>>>;
  countLIKE?: InputMaybe<Scalars['u64']>;
  countLT?: InputMaybe<Scalars['u64']>;
  countLTE?: InputMaybe<Scalars['u64']>;
  countNEQ?: InputMaybe<Scalars['u64']>;
  countNOTIN?: InputMaybe<Array<InputMaybe<Scalars['u64']>>>;
  countNOTLIKE?: InputMaybe<Scalars['u64']>;
  player_id?: InputMaybe<Scalars['ContractAddress']>;
  player_idEQ?: InputMaybe<Scalars['ContractAddress']>;
  player_idGT?: InputMaybe<Scalars['ContractAddress']>;
  player_idGTE?: InputMaybe<Scalars['ContractAddress']>;
  player_idIN?: InputMaybe<Array<InputMaybe<Scalars['ContractAddress']>>>;
  player_idLIKE?: InputMaybe<Scalars['ContractAddress']>;
  player_idLT?: InputMaybe<Scalars['ContractAddress']>;
  player_idLTE?: InputMaybe<Scalars['ContractAddress']>;
  player_idNEQ?: InputMaybe<Scalars['ContractAddress']>;
  player_idNOTIN?: InputMaybe<Array<InputMaybe<Scalars['ContractAddress']>>>;
  player_idNOTLIKE?: InputMaybe<Scalars['ContractAddress']>;
  quest_id?: InputMaybe<Scalars['felt252']>;
  quest_idEQ?: InputMaybe<Scalars['felt252']>;
  quest_idGT?: InputMaybe<Scalars['felt252']>;
  quest_idGTE?: InputMaybe<Scalars['felt252']>;
  quest_idIN?: InputMaybe<Array<InputMaybe<Scalars['felt252']>>>;
  quest_idLIKE?: InputMaybe<Scalars['felt252']>;
  quest_idLT?: InputMaybe<Scalars['felt252']>;
  quest_idLTE?: InputMaybe<Scalars['felt252']>;
  quest_idNEQ?: InputMaybe<Scalars['felt252']>;
  quest_idNOTIN?: InputMaybe<Array<InputMaybe<Scalars['felt252']>>>;
  quest_idNOTLIKE?: InputMaybe<Scalars['felt252']>;
};

export type Dojo_World_QuestEdge = {
  __typename?: 'dojo_world_QuestEdge';
  cursor?: Maybe<Scalars['Cursor']>;
  node?: Maybe<Dojo_World_Quest>;
};

export type Dojo_World_QuestOrder = {
  direction: OrderDirection;
  field: Dojo_World_QuestOrderField;
};

export enum Dojo_World_QuestOrderField {
  Availability = 'AVAILABILITY',
  Completion = 'COMPLETION',
  Desc = 'DESC',
  External = 'EXTERNAL',
  Id = 'ID',
  ImageUri = 'IMAGE_URI',
  Name = 'NAME',
  QuestType = 'QUEST_TYPE'
}

export type Dojo_World_QuestWhereInput = {
  desc?: InputMaybe<Scalars['ByteArray']>;
  descEQ?: InputMaybe<Scalars['ByteArray']>;
  descGT?: InputMaybe<Scalars['ByteArray']>;
  descGTE?: InputMaybe<Scalars['ByteArray']>;
  descIN?: InputMaybe<Array<InputMaybe<Scalars['ByteArray']>>>;
  descLIKE?: InputMaybe<Scalars['ByteArray']>;
  descLT?: InputMaybe<Scalars['ByteArray']>;
  descLTE?: InputMaybe<Scalars['ByteArray']>;
  descNEQ?: InputMaybe<Scalars['ByteArray']>;
  descNOTIN?: InputMaybe<Array<InputMaybe<Scalars['ByteArray']>>>;
  descNOTLIKE?: InputMaybe<Scalars['ByteArray']>;
  id?: InputMaybe<Scalars['felt252']>;
  idEQ?: InputMaybe<Scalars['felt252']>;
  idGT?: InputMaybe<Scalars['felt252']>;
  idGTE?: InputMaybe<Scalars['felt252']>;
  idIN?: InputMaybe<Array<InputMaybe<Scalars['felt252']>>>;
  idLIKE?: InputMaybe<Scalars['felt252']>;
  idLT?: InputMaybe<Scalars['felt252']>;
  idLTE?: InputMaybe<Scalars['felt252']>;
  idNEQ?: InputMaybe<Scalars['felt252']>;
  idNOTIN?: InputMaybe<Array<InputMaybe<Scalars['felt252']>>>;
  idNOTLIKE?: InputMaybe<Scalars['felt252']>;
  name?: InputMaybe<Scalars['ByteArray']>;
  nameEQ?: InputMaybe<Scalars['ByteArray']>;
  nameGT?: InputMaybe<Scalars['ByteArray']>;
  nameGTE?: InputMaybe<Scalars['ByteArray']>;
  nameIN?: InputMaybe<Array<InputMaybe<Scalars['ByteArray']>>>;
  nameLIKE?: InputMaybe<Scalars['ByteArray']>;
  nameLT?: InputMaybe<Scalars['ByteArray']>;
  nameLTE?: InputMaybe<Scalars['ByteArray']>;
  nameNEQ?: InputMaybe<Scalars['ByteArray']>;
  nameNOTIN?: InputMaybe<Array<InputMaybe<Scalars['ByteArray']>>>;
  nameNOTLIKE?: InputMaybe<Scalars['ByteArray']>;
  quest_type?: InputMaybe<Scalars['Enum']>;
};

export type Dojo_World_Quest_OptionByteArray = {
  __typename?: 'dojo_world_Quest_OptionByteArray';
  Some?: Maybe<Scalars['ByteArray']>;
  option?: Maybe<Scalars['Enum']>;
};

export type Dojo_World_Quest_OptionContractAddress = {
  __typename?: 'dojo_world_Quest_OptionContractAddress';
  Some?: Maybe<Scalars['ContractAddress']>;
  option?: Maybe<Scalars['Enum']>;
};

export type Dojo_World_Quest_QuestRules = {
  __typename?: 'dojo_world_Quest_QuestRules';
  all?: Maybe<Array<Maybe<Dojo_World_Quest_QuestRulesInfos>>>;
  any?: Maybe<Array<Maybe<Dojo_World_Quest_QuestRulesInfos>>>;
};

export type Dojo_World_Quest_QuestRulesInfos = {
  __typename?: 'dojo_world_Quest_QuestRulesInfos';
  count?: Maybe<Scalars['u64']>;
  quest_id?: Maybe<Scalars['felt252']>;
};

export type QuestsQueryVariables = Exact<{ [key: string]: never; }>;


export type QuestsQuery = { __typename?: 'World__Query', dojoWorldQuestModels?: { __typename?: 'dojo_world_QuestConnection', edges?: Array<{ __typename?: 'dojo_world_QuestEdge', node?: { __typename?: 'dojo_world_Quest', id?: any | null, name?: any | null, desc?: any | null, quest_type?: any | null, image_uri?: { __typename?: 'dojo_world_Quest_OptionByteArray', Some?: any | null } | null, external?: { __typename?: 'dojo_world_Quest_OptionContractAddress', Some?: any | null } | null } | null } | null> | null } | null };


export const QuestsDocument = `
    query Quests {
  dojoWorldQuestModels {
    edges {
      node {
        id
        name
        desc
        image_uri {
          Some
        }
        quest_type
        external {
          Some
        }
      }
    }
  }
}
    `;
export const useQuestsQuery = <
      TData = QuestsQuery,
      TError = unknown
    >(
      variables?: QuestsQueryVariables,
      options?: UseQueryOptions<QuestsQuery, TError, TData>
    ) =>
    useQuery<QuestsQuery, TError, TData>(
      variables === undefined ? ['Quests'] : ['Quests', variables],
      useFetchData<QuestsQuery, QuestsQueryVariables>(QuestsDocument).bind(null, variables),
      options
    );

useQuestsQuery.getKey = (variables?: QuestsQueryVariables) => variables === undefined ? ['Quests'] : ['Quests', variables];
;

export const useInfiniteQuestsQuery = <
      TData = QuestsQuery,
      TError = unknown
    >(
      variables?: QuestsQueryVariables,
      options?: UseInfiniteQueryOptions<QuestsQuery, TError, TData>
    ) =>{
    const query = useFetchData<QuestsQuery, QuestsQueryVariables>(QuestsDocument)
    return useInfiniteQuery<QuestsQuery, TError, TData>(
      variables === undefined ? ['Quests.infinite'] : ['Quests.infinite', variables],
      (metaData) => query({...variables, ...(metaData.pageParam ?? {})}),
      options
    )};


useInfiniteQuestsQuery.getKey = (variables?: QuestsQueryVariables) => variables === undefined ? ['Quests.infinite'] : ['Quests.infinite', variables];
;
