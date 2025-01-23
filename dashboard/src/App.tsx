import { Center, Container, Tabs, Stack } from "@chakra-ui/react"
import Header from "./components/Header"
import { LuLayoutDashboard, LuSettings } from "react-icons/lu"
import { AppGroupModel } from "./types"
import AppGroup from "./components/AppGroup"

const AllApps: AppGroupModel[] = [
  {
    groupName: "Operation",
    apps: [
      {
        title: "Proxmox",
        description: "aaaaa",
        url: "https://192.168.5.21:8006",
      },
      {
        title: "Grafana",
        description: "",
        url: "http://192.168.5.100:81",
        links: [
          {
            text: "Dashboards",
            url: "http://192.168.5.100:81/dashboards",
          },
        ],
      },
      {
        title: "Argo Workflow",
        description: "",
        url: "https://192.168.5.100:82",
      },
    ],
  },
  {
    groupName: "Pechka",
    apps: [
      {
        title: "File server",
        description: "aaa",
        url: "http://192.168.5.100:8001",
      },
    ],
  },
]

export default function App() {
  return (
    <Center>
      <Container maxWidth="1200px">
        <Stack gap="4" direction="column">
          <Header />

          <Container>
            <Tabs.Root defaultValue="home">
              <Tabs.List>
                <Tabs.Trigger value="home">
                  <LuLayoutDashboard /> Home
                </Tabs.Trigger>
                <Tabs.Trigger value="settings">
                  <LuSettings /> Settings
                </Tabs.Trigger>
              </Tabs.List>
              <Tabs.Content value="home">
                <Stack gap="4">
                  {AllApps.map((appGroup) => (
                    <AppGroup key={appGroup.groupName} {...appGroup} />
                  ))}
                </Stack>
              </Tabs.Content>

              <Tabs.Content value="settings">todo</Tabs.Content>
            </Tabs.Root>
          </Container>
        </Stack>
      </Container>
    </Center>
  )
}
