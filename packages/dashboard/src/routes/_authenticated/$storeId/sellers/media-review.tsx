import { adminClient, getApiClient, useAuth } from '@spree/dashboard-core'
import {
  Alert,
  AlertDescription,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Input,
  Label,
  Textarea,
} from '@spree/dashboard-ui'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { createFileRoute } from '@tanstack/react-router'
import { useEffect, useState } from 'react'

export const Route = createFileRoute('/_authenticated/$storeId/sellers/media-review')({
  component: CreatorMediaReviewPage,
})

type PreviewItem = {
  preview_url: string
  file_name: string
  content_type: string
}

function AuthenticatedMediaPreview({ item }: { item: PreviewItem }) {
  const { token } = useAuth()
  const [objectUrl, setObjectUrl] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const controller = new AbortController()
    let active = true
    let createdUrl: string | null = null

    async function loadPreview() {
      try {
        setError(null)
        setObjectUrl(null)

        const apiBaseUrl = import.meta.env.VITE_SPREE_API_URL || ''
        const url =
          item.preview_url.startsWith('http://') || item.preview_url.startsWith('https://')
            ? item.preview_url
            : `${apiBaseUrl}${item.preview_url}`
        const apiOrigin = apiBaseUrl ? new URL(apiBaseUrl).origin : window.location.origin
        const sameOrigin = new URL(url, window.location.origin).origin === apiOrigin
        const headers: Record<string, string> = {}

        if (sameOrigin && token) {
          headers.Authorization = `Bearer ${token}`
          Object.assign(headers, getApiClient().downloadHeaders?.() ?? {})
        }

        const response = await fetch(url, {
          headers,
          credentials: sameOrigin ? 'include' : 'omit',
          signal: controller.signal,
        })
        if (!response.ok) throw new Error(`Preview unavailable (${response.status})`)

        const blob = await response.blob()
        if (!active) return
        createdUrl = URL.createObjectURL(blob)
        setObjectUrl(createdUrl)
      } catch (cause) {
        if (!active || (cause instanceof DOMException && cause.name === 'AbortError')) return
        setError(cause instanceof Error ? cause.message : 'Could not load private preview.')
      }
    }

    void loadPreview()
    return () => {
      active = false
      controller.abort()
      if (createdUrl) URL.revokeObjectURL(createdUrl)
    }
  }, [item.preview_url, token])

  if (error) return <p className="text-sm text-destructive">{error}</p>
  if (!objectUrl) return <p className="text-sm text-muted-foreground">Loading secure preview…</p>

  if (item.content_type.startsWith('image/')) {
    return (
      <img
        src={objectUrl}
        alt={item.file_name}
        className="max-h-[480px] max-w-full rounded-md object-contain"
      />
    )
  }
  if (item.content_type.startsWith('video/')) {
    // Uploaded source videos may not include caption files; reviewers inspect the original media.
    return (
      // biome-ignore lint/a11y/useMediaCaption: source uploads are reviewed as submitted and have no generated caption track.
      <video src={objectUrl} controls playsInline className="max-h-[480px] max-w-full rounded-md" />
    )
  }
  if (item.content_type === 'application/pdf') {
    return (
      <a className="text-sm underline" href={objectUrl} target="_blank" rel="noreferrer">
        Open private PDF preview
      </a>
    )
  }
  return (
    <p className="text-sm text-muted-foreground">
      No inline preview is available for this file type.
    </p>
  )
}

function CreatorMediaReviewPage() {
  const queryClient = useQueryClient()
  const [reasonCode, setReasonCode] = useState('policy_violation')
  const [notes, setNotes] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)

  const queue = useQuery({
    queryKey: ['digital-asset-versions', 'published'],
    queryFn: () => adminClient.digitalAssetVersions.list({ status: 'published' }),
  })

  const decision = useMutation({
    mutationFn: async ({ id }: { id: string }) => adminClient.digitalAssetVersions.remove(id, {
      reason_code: reasonCode.trim(),
      notes: notes.trim() || undefined,
    }),
    onSuccess: async () => {
      setSelectedId(null)
      setNotes('')
      await queryClient.invalidateQueries({ queryKey: ['digital-asset-versions'] })
    },
  })

  const items = queue.data?.data ?? []

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Creator publications</h1>
        <p className="text-sm text-muted-foreground">
          Published creator content. Remove a publication only when it breaches the platform rules.
        </p>
      </header>

      {queue.isError && (
        <Alert variant="destructive">
          <AlertDescription>
            Could not load the publication list. Check your permissions and try again.
          </AlertDescription>
        </Alert>
      )}

      {decision.isError && (
        <Alert variant="destructive">
          <AlertDescription>
            {(decision.error as Error).message || 'The removal failed.'}
          </AlertDescription>
        </Alert>
      )}

      {queue.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading published creator content…</p>
      ) : items.length === 0 ? (
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            There are no published creator files.
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4">
          {items.map((item) => (
            <Card key={item.id}>
              <CardHeader>
                <CardTitle className="text-base">{item.file_name}</CardTitle>
                <p className="text-sm text-muted-foreground">
                  Creator: {item.seller_name || 'Unassigned'} · Product: {item.product_title} ·
                  Revision {item.version_number}
                </p>
                <p className="text-xs text-muted-foreground">
                  {item.content_type} · {(item.byte_size / 1024 / 1024).toFixed(2)} MB · Submitted{' '}
                  {new Date(item.submitted_at).toLocaleString()}
                </p>
              </CardHeader>
              <CardContent className="flex flex-col gap-4">
                <AuthenticatedMediaPreview item={item} />

                {selectedId === item.id && (
                  <div className="grid gap-2 rounded-md border p-3">
                    <Label htmlFor={`reason-${item.id}`}>Removal reason code</Label>
                    <Input
                      id={`reason-${item.id}`}
                      value={reasonCode}
                      onChange={(event) => setReasonCode(event.target.value)}
                    />
                    <Label htmlFor={`notes-${item.id}`}>Review notes</Label>
                    <Textarea
                      id={`notes-${item.id}`}
                      value={notes}
                      onChange={(event) => setNotes(event.target.value)}
                      rows={3}
                    />
                    <div className="flex flex-wrap gap-2">
                      <Button
                        variant="destructive"
                        disabled={!reasonCode.trim() || decision.isPending}
                        onClick={() => decision.mutate({ id: item.id })}
                      >
                        Confirm removal
                      </Button>
                      <Button
                        variant="outline"
                        disabled={decision.isPending}
                        onClick={() => setSelectedId(null)}
                      >
                        Cancel
                      </Button>
                    </div>
                  </div>
                )}

                <div className="flex flex-wrap gap-2">
                  <p className="text-sm text-muted-foreground">Status: {item.status}</p>
                  <Button
                    variant="destructive"
                    disabled={decision.isPending || selectedId !== null}
                    onClick={() => {
                      setSelectedId(item.id)
                      setReasonCode('policy_violation')
                      setNotes('')
                    }}
                  >
                    Remove publication
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
