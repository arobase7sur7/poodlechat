import { colorToCss, ensureString, formatTimestamp, messageAuthor, messageBody, messageRawText, renderRichText, stripRichText } from '../../richText';
import { asRecord } from '../../utils';
import type { ChatMessage } from '../../types';
import type { MouseEvent } from 'react';
import { memo, useMemo } from 'react';

export function messageKey(message: ChatMessage, index: number): string {
  return ensureString(message.messageId || message._id, `message:${index}`);
}

export function createReportContext(message: ChatMessage) {
  const metadata = asRecord(message.metadata);
  const body = messageBody(message);
  const rawMessage = messageRawText(message);
  return {
    messageId: message.messageId,
    channel: message.channel,
    label: message.label,
    type: metadata.type || 'chat',
    authorName: messageAuthor(message),
    authorSource: metadata.authorSource || metadata.source,
    peerId: metadata.peerId,
    peerCharacterId: metadata.peerCharacterId,
    conversationId: metadata.conversationId,
    timestamp: message.timestamp,
    rawMessage,
    renderedMessage: stripRichText(rawMessage).slice(0, 500),
    excerpt: stripRichText(body).slice(0, 180),
    args: message.args,
    template: message.template,
    metadata
  };
}

function identityLine(label: string, value: unknown) {
  const record = asRecord(value);
  const source = ensureString(record.source || record.id || '');
  const name = ensureString(record.name || record.realName || '');
  const discord = ensureString(record.discord || '');
  const citizenid = ensureString(record.citizenid || '');
  const license = ensureString(record.license || record.identifier || '');
  if (!source && !name && !discord && !citizenid && !license) {
    return null;
  }
  return (
    <div className="report-identity">
      <strong>{label}</strong>
      <span>{source ? `ID ${source}` : 'ID ?'} {name}</span>
      {discord && <code>{discord}</code>}
      {citizenid && <code>{citizenid}</code>}
      {license && <code>{license}</code>}
    </div>
  );
}

function MessageRow({
  message,
  onContext,
  hideDeleted,
  selected
}: {
  message: ChatMessage;
  onContext: (event: MouseEvent, message: ChatMessage) => void;
  hideDeleted: boolean;
  selected?: boolean;
}) {
  const metadata = asRecord(message.metadata);
  const deleted = metadata.deleted === true;
  const visibleOriginal = metadata.deletedVisibleOriginal === true;
  const type = ensureString(metadata.type, 'chat');
  const author = messageAuthor(message);
  const body = deleted && hideDeleted && !visibleOriginal ? 'Message deleted' : messageBody(message);
  const labelKey = ensureString(message.label).trim().toLowerCase();
  const authorName = ensureString(metadata.authorName || author);
  const actionAuthor = author.trim().startsWith('*') ? author : `* ${authorName}`;
  const isActionMessage = type === 'action' || type === 'me' || labelKey === 'me' || author.trim().startsWith('* ');
  const isSceneMessage = type === 'scene' || type === 'do' || labelKey === 'do';
  const variant =
    type === 'join' || type === 'leave'
      ? 'presence'
      : type === 'report'
        ? 'report'
        : isActionMessage
          ? 'action'
          : isSceneMessage
            ? 'scene'
            : type === 'system' || ensureString(message.label) === 'System' || type === 'delete'
          ? 'system'
          : 'chat';
  const reportContext = asRecord(metadata.reportContext);
  const reporter = asRecord(metadata.reporter);
  const target = asRecord(metadata.target);
  const reportReason = ensureString(metadata.reason || body);
  const renderedAuthor = useMemo(() => renderRichText(author), [author]);
  const renderedActionAuthor = useMemo(() => renderRichText(actionAuthor), [actionAuthor]);
  const renderedSceneAuthor = useMemo(() => renderRichText(authorName), [authorName]);
  const renderedBody = useMemo(() => renderRichText(body), [body]);

  if (variant === 'presence') {
    const presenceType = type === 'leave' ? 'leave' : 'join';
    return (
      <div
        className={`msg msg-presence msg-${presenceType}${selected ? ' msg-selected' : ''}`}
        data-message-id={message.messageId || ''}
        onContextMenu={(event) => onContext(event, message)}
      >
        <div className="presence-line">
          <span className="presence-symbol" aria-hidden="true">{presenceType === 'leave' ? '-' : '+'}</span>
          <span className="presence-player" dangerouslySetInnerHTML={{ __html: renderedAuthor }} />
          <span className="presence-body" dangerouslySetInnerHTML={{ __html: renderedBody }} />
          <time>{formatTimestamp(message.timestamp)}</time>
        </div>
      </div>
    );
  }

  return (
    <div
      className={`msg msg-${variant}${deleted ? ' msg-deleted' : ''}${message.restored ? ' msg-restored' : ''}${selected ? ' msg-selected' : ''}`}
      data-message-id={message.messageId || ''}
      onContextMenu={(event) => onContext(event, message)}
    >
      <div className="msg-meta">
        <span className="msg-chip">{ensureString(message.label, 'Chat')}</span>
        <span className="msg-time">{formatTimestamp(message.timestamp)}</span>
      </div>
      <div className="msg-line">
        {variant === 'chat' && (
          <span className="msg-author" style={{ color: colorToCss(message.color) }} dangerouslySetInnerHTML={{ __html: renderedAuthor }} />
        )}
        {variant === 'action' && (
          <span className="msg-author msg-rp-author" style={{ color: colorToCss(message.color) }} dangerouslySetInnerHTML={{ __html: renderedActionAuthor }} />
        )}
        {variant === 'scene' && (
          <span className="msg-scene-marker">Scene</span>
        )}
        <span
          className={`msg-body${deleted && hideDeleted && !visibleOriginal ? ' msg-obscured' : ''}`}
          dangerouslySetInnerHTML={{ __html: renderedBody }}
        />
        {variant === 'scene' && authorName && (
          <span className="msg-scene-author" dangerouslySetInnerHTML={{ __html: renderedSceneAuthor }} />
        )}
        {deleted && <span className="msg-chip msg-chip-muted">Deleted</span>}
      </div>
      {variant === 'report' && (
        <div className="report-details">
          {identityLine('Reporter', Object.keys(reporter).length > 0 ? reporter : { source: metadata.reporterSource, name: metadata.reporterName })}
          {identityLine('Reported', Object.keys(target).length > 0 ? target : { source: metadata.targetSource, name: metadata.targetName })}
          {reportReason && <div><strong>Reason</strong><span>{reportReason}</span></div>}
          {ensureString(reportContext.renderedMessage || reportContext.excerpt) && <div><strong>Message</strong><span>{ensureString(reportContext.renderedMessage || reportContext.excerpt)}</span></div>}
          {ensureString(reportContext.rawMessage) && <div><strong>Raw</strong><code>{ensureString(reportContext.rawMessage)}</code></div>}
        </div>
      )}
    </div>
  );
}

export default memo(MessageRow);
