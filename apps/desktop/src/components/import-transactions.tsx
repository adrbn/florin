'use client'

import { useState, useCallback, useRef } from 'react'
import { Upload, FileText, CheckCircle2, AlertCircle } from 'lucide-react'
import { cn } from '@florin/core/lib/utils'
import { importTransactions } from '@/server/actions/import'

interface ImportTransactionsProps {
  accountId: string
  accountName: string
}

type ImportState =
  | { status: 'idle' }
  | { status: 'dragging' }
  | { status: 'importing'; fileName: string }
  | { status: 'success'; imported: number; skipped: number }
  | { status: 'error'; message: string }

export function ImportTransactions({ accountId, accountName }: ImportTransactionsProps) {
  const [state, setState] = useState<ImportState>({ status: 'idle' })
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleFile = useCallback(
    async (file: File) => {
      setState({ status: 'importing', fileName: file.name })
      try {
        const content = await file.text()
        const result = await importTransactions(accountId, content, file.name)
        if (result.success && result.data) {
          setState({
            status: 'success',
            imported: result.data.imported,
            skipped: result.data.skipped,
          })
        } else {
          setState({ status: 'error', message: result.error ?? 'Import failed' })
        }
      } catch {
        setState({ status: 'error', message: 'Failed to read file' })
      }
    },
    [accountId],
  )

  function handleDrop(e: React.DragEvent) {
    e.preventDefault()
    e.stopPropagation()
    setState({ status: 'idle' })
    const file = e.dataTransfer.files[0]
    if (file) void handleFile(file)
  }

  function handleDragOver(e: React.DragEvent) {
    e.preventDefault()
    e.stopPropagation()
    setState({ status: 'dragging' })
  }

  function handleDragLeave(e: React.DragEvent) {
    e.preventDefault()
    e.stopPropagation()
    setState({ status: 'idle' })
  }

  function handleInputChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (file) void handleFile(file)
  }

  const isDragging = state.status === 'dragging'
  const isImporting = state.status === 'importing'

  return (
    <div className="space-y-3">
      <div
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onClick={() => fileInputRef.current?.click()}
        className={cn(
          'flex cursor-pointer flex-col items-center gap-2 rounded-lg border-2 border-dashed p-6 text-center transition-colors',
          isDragging
            ? 'border-primary bg-primary/5'
            : 'border-border hover:border-primary/50 hover:bg-muted/50',
          isImporting && 'pointer-events-none opacity-60',
        )}
      >
        {state.status === 'importing' ? (
          <>
            <FileText className="h-8 w-8 animate-pulse text-primary" />
            <p className="text-sm font-medium">Importing {state.fileName}...</p>
          </>
        ) : (
          <>
            <Upload className="h-8 w-8 text-muted-foreground" />
            <div>
              <p className="text-sm font-medium">
                Drop CSV or OFX file here
              </p>
              <p className="text-xs text-muted-foreground">
                Import bank statements into {accountName}
              </p>
            </div>
          </>
        )}
        <input
          ref={fileInputRef}
          type="file"
          accept=".csv,.ofx,.qfx,.tsv"
          className="hidden"
          onChange={handleInputChange}
        />
      </div>

      {state.status === 'success' && (
        <div className="flex items-center gap-2 rounded-md bg-green-500/10 px-3 py-2 text-sm text-green-700 dark:text-green-300">
          <CheckCircle2 className="h-4 w-4 shrink-0" />
          <span>
            Imported {state.imported} transaction{state.imported !== 1 ? 's' : ''}.
            {state.skipped > 0 && ` ${state.skipped} skipped.`}
          </span>
        </div>
      )}

      {state.status === 'error' && (
        <div className="flex items-center gap-2 rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
          <AlertCircle className="h-4 w-4 shrink-0" />
          <span>{state.message}</span>
        </div>
      )}
    </div>
  )
}
