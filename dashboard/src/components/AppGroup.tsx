import { Heading, Stack } from "@chakra-ui/react"
import AppCard from "./AppCard"
import { AppGroupModel } from "@/types"

type Props = AppGroupModel & {}
export default function AppGroup({ groupName, apps }: Props) {
  return (
    <Stack>
      <Heading as="h2">{groupName}</Heading>

      <Stack direction="row" align="flex-start" wrap="wrap">
        {apps.map((app) => (
          <AppCard {...app} key={app.title} />
        ))}
      </Stack>
    </Stack>
  )
}
