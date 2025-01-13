
export type AppModel = {
  title: string
  description: string
  url: string
  links?: AppLinkModel[]
}

export type AppLinkModel = {
  text: string
  url: string
}

export type AppGroupModel = {
  groupName: string
  apps: AppModel[]
}