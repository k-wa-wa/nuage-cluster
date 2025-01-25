import { Card, Link, Button } from "@chakra-ui/react"
import { LuExternalLink } from "react-icons/lu"
import { AppModel } from "@/types"

type Props = AppModel & {}
export default function AppCard({ title, description, url, links }: Props) {
  return (
    <Card.Root w="100%" h="100%">
      <Card.Body>
        <Card.Title>
          <Link href={url} target="_blank" rel="noopener noreferrer">
            {title}
          </Link>
        </Card.Title>
        <Card.Description>{description}</Card.Description>
      </Card.Body>
      <Card.Footer>
        {links ? (
          links.map(({ text, url }) => (
            <Button
              key={text}
              onClick={(e) => {
                e.stopPropagation()
                window.open(url, "_blank")
              }}
            >
              {text} <LuExternalLink />
            </Button>
          ))
        ) : (
          <Button
            onClick={(e) => {
              e.stopPropagation()
              window.open(url, "_blank")
            }}
          >
            Visit <LuExternalLink />
          </Button>
        )}
      </Card.Footer>
    </Card.Root>
  )
}
