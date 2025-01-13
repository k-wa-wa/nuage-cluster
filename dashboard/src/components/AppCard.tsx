import { Card, Link, Button } from "@chakra-ui/react"
import { LuExternalLink } from "react-icons/lu"
import { AppModel } from "@/types"

type Props = AppModel & {}
export default function AppCard({ title, description, url, links }: Props) {
  return (
    <Link href={url} key={title} target="_blank" rel="noopener noreferrer">
      <Card.Root key={title}>
        <Card.Body>
          <Card.Title>{title} </Card.Title>
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
            <Button>
              Visit <LuExternalLink />
            </Button>
          )}
        </Card.Footer>
      </Card.Root>
    </Link>
  )
}
