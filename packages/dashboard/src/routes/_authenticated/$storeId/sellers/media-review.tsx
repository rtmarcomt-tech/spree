import { adminClient } from '@spree/dashboard-core'
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
import { createFileRoute } from '@tanstack/react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'

export const Route = createFileRoute('/_authenticated/$storeId/sellers/media-review')({
  component: CreatorMediaReviewPage,
})

function CreatorMediaReviewPage() {
  const queryClient = useQueryClient()
  const [reasonCode, setReasonCode] = useState('policy_violation')
  const [notes, setNotes] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)

  const queue = useQuery({
    queryKey: ['digital-asset-versions', 'pending'],
    queryFn: () => adminClient.digitalAssetVersions.list({ status: 'pending' }),
  })

  const decision = useMutation({
    mutationFn: async ({ id, approve }: { id: string; approve: boolean }) => {
      if (approve) {
        return adminClient.digitalAssetVersions.approve(id, { notes: notes || undefined })
      }
      return adminClient.digitalAssetVersions.reject(id, {
        reason_code: reasonCode.trim(),
        notes: notes.trim() || undefined,
      })
    },
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
        <h1 className="text-2xl font-semibold">Creator content review</h1>
        <p className="text-sm text-muted-foreground">
          Review each uploaded revision before it can appear in the storefront or be purchased.
        </p>
      </header>

      {queue.isError && (
        <Alert variant="destructive">
          <AlertDescription>Could not load the moderation queue. Check your permissions and try again.</AlertDescription>
        </Alert>
      )}

      {decision.isError && (
        <Alert variant="destructive">
          <AlertDescription>{(decision.error as Error).message || 'The moderation decision failed.'}</AlertDescription>
        </Alert>
      )}

      {queue.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading pending uploads…</p>
      ) : items.length === 0 ? (
        <Card><CardContent className="py-8 text-center text-sm text-muted-foreground">There are no uploads waiting for review.</CardContent></Card>
      ) : (
        <div className="grid gap-4">
          {items.map((item) => (
            <Card key={item.id}>
              <CardHeader>
                <CardTitle className="text-base">{item.file_name}</CardTitle>
                <p className="text-sm text-muted-foreground">
                  Creator: {item.seller_name || 'Unassigned'} · Product: {item.product_title} · Revision {item.version_number}
                </p>
                <p className="text-xs text-muted-foreground">
                  {item.content_type} · {(item.byte_size / 1024 / 1024).toFixed(2)} MB · Submitted {new Date(item.submitted_at).toLocaleString()}
                </p>
              </CardHeader>
              <CardContent className="flex flex-col gap-4">
                {item.content_type.startsWith('image/') ? (
                  <img src={item.preview_url} alt={item.file_name} className="max-h-[480px] max-w-full rounded-md object-contain" />
                ) : item.content_type.startsWith('video/') ? (
                  <video src={item.preview_url} controls playsInline className="max-h-[480px] max-w-full rounded-md" />
                ) : item.content_type === 'application/pdf' ? (
                  <a className="text-sm underline" href={item.preview_url} target="_blank" rel="noreferrer">Open private PDF preview</a>
                ) : (
                  <p className="text-sm text-muted-foreground">No inline preview is available for this file type.</p>
                )}

                {selectedId === item.id && (
                  <div className="grid gap-2 rounded-md border p-3">
                    <Label htmlFor={`reason-${item.id}`}>Rejection reason code</Label>
                    <Input id={`reason-${item.id}`} value={reasonCode} onChange={(event) => setReasonCode(event.target.value)} />
                    <Label htmlFor={`notes-${item.id}`}>Review notes</Label>
                    <Textarea id={`notes-${item.id}`} value={notes} onChange={(event) => setNotes(event.target.value)} rows={3} />
                    <div className="flex flex-wrap gap-2">
                      <Button
                        variant="destructive"
                        disabled={!reasonCode.trim() || decision.isPending}
                        onClick={() => decision.mutate({ id: item.id, approve: false })}
                      >
                        Confirm rejection
                      </Button>
                      <Button variant="outline" disabled={decision.isPending} onClick={() => setSelectedId(null)}>Cancel</Button>
                    </div>
                  </div>
                )}

                <div className="flex flex-wrap gap-2">
                  <Button disabled={decision.isPending || selectedId !== null} onClick={() => decision.mutate({ id: item.id, approve: true })}>
                    Approve revision
                  </Button>
                  <Button variant="destructive" disabled={decision.isPending || selectedId !== null} onClick={() => { setSelectedId(item.id); setReasonCode('policy_violation'); setNotes('') }}>
                    Reject revision
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
