"use client";

import { useEffect, useState, useCallback, useRef } from "react";
import { motion, AnimatePresence } from "motion/react";
import { getLastTournamentCode, getMemberToken } from "@/lib/tokenStorage";
import { getBrowserClient } from "@/lib/supabase-browser";

// ─── Types ────────────────────────────────────────────────────────────────────

interface SocialProfile {
  id: string;
  username: string;
  photo_url: string | null;
}

interface Post {
  id: string;
  content: string | null;
  image_url: string | null;
  created_at: string;
  parent_id: string | null;
  isMe: boolean;
  author: { username: string; photo_url: string | null } | null;
  likeCount: number;
  likedByMe: boolean;
  replyCount: number;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function timeAgo(iso: string): string {
  const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (diff < 60) return "ahora";
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  return `${Math.floor(diff / 86400)}d`;
}

function Avatar({
  photo_url,
  username,
  size = 40,
}: {
  photo_url?: string | null;
  username?: string | null;
  size?: number;
}) {
  if (photo_url) {
    return (
      <img
        src={photo_url}
        alt={username ?? ""}
        style={{ width: size, height: size }}
        className="rounded-full object-cover shrink-0"
      />
    );
  }
  return (
    <div
      style={{ width: size, height: size, fontSize: size * 0.4 }}
      className="rounded-full bg-gradient-to-br from-[#8B5CF6] to-[#6D28D9] flex items-center justify-center shrink-0 font-bold text-white"
    >
      {(username ?? "?").charAt(0).toUpperCase()}
    </div>
  );
}

function compressImage(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        const MAX = 900;
        let { width, height } = img;
        if (width > MAX) { height = Math.round((height * MAX) / width); width = MAX; }
        const canvas = document.createElement("canvas");
        canvas.width = width; canvas.height = height;
        canvas.getContext("2d")!.drawImage(img, 0, 0, width, height);
        resolve(canvas.toDataURL("image/jpeg", 0.75));
      };
      img.onerror = reject;
      img.src = e.target!.result as string;
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

function compressAvatar(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        const SIZE = 200;
        const min = Math.min(img.width, img.height);
        const sx = (img.width - min) / 2; const sy = (img.height - min) / 2;
        const canvas = document.createElement("canvas");
        canvas.width = SIZE; canvas.height = SIZE;
        canvas.getContext("2d")!.drawImage(img, sx, sy, min, min, 0, 0, SIZE, SIZE);
        resolve(canvas.toDataURL("image/jpeg", 0.8));
      };
      img.onerror = reject;
      img.src = e.target!.result as string;
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

// ─── Profile Setup Modal ──────────────────────────────────────────────────────

function ProfileSetupModal({
  existing,
  onSave,
  onClose,
}: {
  existing: SocialProfile | null;
  onSave: (profile: SocialProfile) => void;
  onClose?: () => void;
}) {
  const [username, setUsername] = useState(existing?.username ?? "");
  const [photoPreview, setPhotoPreview] = useState<string | null>(existing?.photo_url ?? null);
  const [photoData, setPhotoData] = useState<string | null>(existing?.photo_url ?? null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  const handlePhoto = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const compressed = await compressAvatar(file);
      setPhotoPreview(compressed);
      setPhotoData(compressed);
    } catch { setError("Error procesando imagen"); }
  };

  const handleSave = async () => {
    if (username.trim().length < 2) { setError("El nombre debe tener al menos 2 caracteres"); return; }
    setSaving(true); setError("");
    const code = getLastTournamentCode();
    const token = code ? getMemberToken(code) : null;
    if (!code || !token) { setError("Sin sesión"); setSaving(false); return; }
    try {
      const res = await fetch(`/api/tournaments/${code}/social/profile`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ username: username.trim(), photo_url: photoData }),
      });
      if (!res.ok) { const j = await res.json(); setError(j.error ?? "Error guardando perfil"); return; }
      const { profile } = await res.json();
      onSave(profile);
    } catch { setError("Error de conexión"); }
    finally { setSaving(false); }
  };

  const isEdit = !!existing;

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/60 backdrop-blur-sm">
      <motion.div
        initial={{ opacity: 0, y: 24 }}
        animate={{ opacity: 1, y: 0 }}
        className="bg-[#131722] rounded-t-2xl sm:rounded-2xl border border-white/8 w-full max-w-sm p-5 sm:p-6 shadow-2xl"
      >
        <div className="flex items-center justify-between mb-5">
          <div>
            <h2 className="text-[#F3F4F6] font-bold text-base">
              {isEdit ? "Editar perfil social" : "Configura tu perfil social"}
            </h2>
            <p className="text-[#9CA3AF] text-xs mt-0.5">
              {isEdit ? "Actualiza tu nombre o foto" : "Antes de publicar, elige tu nombre y foto"}
            </p>
          </div>
          {isEdit && onClose && (
            <button onClick={onClose} className="w-7 h-7 rounded-lg hover:bg-[#1A1F2E] flex items-center justify-center text-[#9CA3AF] hover:text-[#F3F4F6] transition-colors cursor-pointer">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
            </button>
          )}
        </div>
        <div className="flex flex-col items-center gap-3 mb-5">
          <div className="relative group">
            {photoPreview ? (
              <img src={photoPreview} alt="Avatar" className="w-20 h-20 rounded-full object-cover border-2 border-[#8B5CF6]/40" />
            ) : (
              <div className="w-20 h-20 rounded-full bg-[#1A1F2E] border-2 border-dashed border-white/15 flex items-center justify-center">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
              </div>
            )}
            <button onClick={() => fileRef.current?.click()} className="absolute inset-0 rounded-full bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center cursor-pointer">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>
            </button>
          </div>
          <button onClick={() => fileRef.current?.click()} className="text-[#8B5CF6] text-xs font-medium hover:text-[#A78BFA] transition-colors cursor-pointer">
            {photoPreview ? "Cambiar foto" : "Subir foto"}
          </button>
          <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={handlePhoto} />
        </div>
        <div className="mb-5">
          <label className="text-[#9CA3AF] text-xs font-medium mb-1.5 block">Nombre de usuario</label>
          <input
            type="text" value={username} onChange={(e) => setUsername(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleSave()}
            placeholder="ej. CrackTotal99" maxLength={24}
            className="w-full bg-[#0D0F14] border border-white/8 rounded-xl px-4 py-2.5 text-[#F3F4F6] text-sm placeholder-[#4B5563] focus:outline-none focus:border-[#8B5CF6]/50 transition-colors"
          />
          <div className="flex justify-end mt-1"><span className="text-[#4B5563] text-[10px]">{username.length}/24</span></div>
        </div>
        {error && <p className="text-[#EF4444] text-xs mb-4 px-3 py-2 bg-[#EF4444]/8 rounded-lg border border-[#EF4444]/20">{error}</p>}
        <button onClick={handleSave} disabled={saving || username.trim().length < 2} className="w-full py-2.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] disabled:opacity-40 disabled:cursor-not-allowed text-white font-semibold text-sm transition-colors cursor-pointer">
          {saving ? "Guardando…" : isEdit ? "Guardar cambios" : "Crear perfil"}
        </button>
      </motion.div>
    </div>
  );
}

// ─── Compose Box ──────────────────────────────────────────────────────────────

function ComposeBox({
  profile,
  onPost,
  parentId,
  replyingTo,
  onCancelReply,
  autoFocus,
}: {
  profile: SocialProfile;
  onPost: (post: Post) => void;
  parentId?: string | null;
  replyingTo?: string | null;
  onCancelReply?: () => void;
  autoFocus?: boolean;
}) {
  const [content, setContent] = useState("");
  const [imageData, setImageData] = useState<string | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [posting, setPosting] = useState(false);
  const [error, setError] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (autoFocus) textareaRef.current?.focus();
  }, [autoFocus]);

  const handleImage = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const compressed = await compressImage(file);
      setImageData(compressed); setImagePreview(compressed);
    } catch { setError("Error procesando imagen"); }
    e.target.value = "";
  };

  const removeImage = () => { setImageData(null); setImagePreview(null); };

  const handlePost = async () => {
    const trimmed = content.trim();
    if (!trimmed && !imageData) return;
    setPosting(true); setError("");
    const code = getLastTournamentCode();
    const token = code ? getMemberToken(code) : null;
    if (!code || !token) { setError("Sin sesión"); setPosting(false); return; }
    try {
      const res = await fetch(`/api/tournaments/${code}/social/posts`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ content: trimmed || null, image_url: imageData, parent_id: parentId || null }),
      });
      if (!res.ok) { const j = await res.json(); setError(j.error ?? "Error publicando"); return; }
      const { post } = await res.json();
      onPost(post);
      setContent(""); setImageData(null); setImagePreview(null);
      if (textareaRef.current) textareaRef.current.style.height = "auto";
      if (onCancelReply) onCancelReply();
    } catch { setError("Error de conexión"); }
    finally { setPosting(false); }
  };

  const autoResize = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setContent(e.target.value);
    e.target.style.height = "auto";
    e.target.style.height = `${e.target.scrollHeight}px`;
  };

  const canPost = (content.trim().length > 0 || !!imageData) && !posting;
  const isReply = !!parentId;

  return (
    <div className={`bg-[#131722] rounded-2xl border border-white/5 p-4 ${isReply ? "mb-3" : "mb-5"}`}>
      {replyingTo && (
        <div className="flex items-center justify-between mb-3 px-1">
          <span className="text-[#8B5CF6] text-xs font-medium">Respondiendo a @{replyingTo}</span>
          {onCancelReply && (
            <button onClick={onCancelReply} className="text-[#4B5563] hover:text-[#9CA3AF] text-xs transition-colors cursor-pointer">Cancelar</button>
          )}
        </div>
      )}
      <div className="flex gap-3">
        <Avatar photo_url={profile.photo_url} username={profile.username} size={isReply ? 32 : 40} />
        <div className="flex-1 min-w-0">
          <textarea
            ref={textareaRef} value={content} onChange={autoResize}
            placeholder={isReply ? "Escribe tu respuesta…" : "¿Qué está pasando en la liga?"}
            maxLength={500} rows={isReply ? 1 : 2}
            className="w-full bg-transparent text-[#F3F4F6] text-sm placeholder-[#4B5563] resize-none focus:outline-none leading-relaxed"
            style={{ minHeight: isReply ? 36 : 56 }}
          />
          {imagePreview && (
            <div className="relative mt-2 rounded-xl overflow-hidden w-fit max-w-full">
              <img src={imagePreview} alt="adjunto" className="max-h-64 rounded-xl object-cover" />
              <button onClick={removeImage} className="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 hover:bg-black/80 flex items-center justify-center transition-colors cursor-pointer">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
              </button>
            </div>
          )}
          {error && <p className="text-[#EF4444] text-xs mt-2">{error}</p>}
          <div className="flex items-center justify-between mt-3 pt-3 border-t border-white/5">
            <div className="flex items-center gap-1">
              <button onClick={() => fileRef.current?.click()} className="w-8 h-8 rounded-lg hover:bg-[#1A1F2E] flex items-center justify-center text-[#9CA3AF] hover:text-[#8B5CF6] transition-colors cursor-pointer" title="Adjuntar imagen">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
              </button>
              <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={handleImage} />
              {content.length > 400 && (
                <span className={`text-[10px] ml-1 ${content.length >= 500 ? "text-[#EF4444]" : "text-[#F59E0B]"}`}>{500 - content.length}</span>
              )}
            </div>
            <button onClick={handlePost} disabled={!canPost} className="px-4 py-1.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] disabled:opacity-30 disabled:cursor-not-allowed text-white text-xs font-bold transition-colors cursor-pointer">
              {posting ? "Publicando…" : isReply ? "Responder" : "Publicar"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Reply Thread ─────────────────────────────────────────────────────────────

function ReplyThread({
  post,
  profile,
  code,
  token,
}: {
  post: Post;
  profile: SocialProfile | null;
  code: string;
  token: string;
}) {
  const [replies, setReplies] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCompose, setShowCompose] = useState(false);

  const fetchReplies = useCallback(async () => {
    try {
      const res = await fetch(`/api/tournaments/${code}/social/posts?parent_id=${post.id}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const { posts: p } = await res.json();
        setReplies(p ?? []);
      }
    } finally { setLoading(false); }
  }, [code, token, post.id]);

  useEffect(() => { fetchReplies(); }, [fetchReplies]);

  const handleNewReply = (reply: Post) => {
    setReplies((prev) => [...prev, reply]);
    setShowCompose(false);
  };

  const handleLikeReply = useCallback(async (postId: string) => {
    setReplies((prev) =>
      prev.map((p) =>
        p.id === postId
          ? { ...p, likedByMe: !p.likedByMe, likeCount: p.likedByMe ? p.likeCount - 1 : p.likeCount + 1 }
          : p
      )
    );
    try {
      await fetch(`/api/tournaments/${code}/social/posts/${postId}/like`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      });
    } catch {
      setReplies((prev) =>
        prev.map((p) =>
          p.id === postId
            ? { ...p, likedByMe: !p.likedByMe, likeCount: p.likedByMe ? p.likeCount - 1 : p.likeCount + 1 }
            : p
        )
      );
    }
  }, [code, token]);

  return (
    <div className="mt-3 pl-4 border-l-2 border-white/5">
      {loading ? (
        <div className="flex items-center gap-2 py-2">
          <div className="w-4 h-4 border border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
          <span className="text-[#4B5563] text-xs">Cargando respuestas…</span>
        </div>
      ) : (
        <>
          <div className="flex flex-col gap-2 mb-2">
            {replies.map((reply) => (
              <motion.div key={reply.id} initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }}>
                <div className="bg-[#0D0F14] rounded-xl border border-white/4 p-3">
                  <div className="flex items-start gap-2 mb-2">
                    <Avatar photo_url={reply.author?.photo_url} username={reply.author?.username} size={28} />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-1.5">
                        <span className="text-[#F3F4F6] text-xs font-semibold truncate">{reply.author?.username ?? "Usuario"}</span>
                        {reply.isMe && <span className="text-[8px] font-bold px-1 py-0.5 rounded-full bg-[#8B5CF6]/15 text-[#8B5CF6] uppercase tracking-wide shrink-0">tú</span>}
                        <span className="text-[#4B5563] text-[10px]">{timeAgo(reply.created_at)}</span>
                      </div>
                    </div>
                  </div>
                  {reply.content && <p className="text-[#D1D5DB] text-xs leading-relaxed whitespace-pre-wrap break-words mb-2">{reply.content}</p>}
                  {reply.image_url && (
                    <div className="mb-2 rounded-lg overflow-hidden"><img src={reply.image_url} alt="imagen" className="w-full max-h-48 object-cover" /></div>
                  )}
                  <button
                    onClick={() => handleLikeReply(reply.id)}
                    className={`flex items-center gap-1 text-[10px] font-medium transition-colors cursor-pointer group ${reply.likedByMe ? "text-[#EF4444]" : "text-[#4B5563] hover:text-[#EF4444]"}`}
                  >
                    <svg width="12" height="12" viewBox="0 0 24 24" fill={reply.likedByMe ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="transition-transform group-active:scale-125">
                      <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
                    </svg>
                    {reply.likeCount > 0 && <span className="tabular-nums">{reply.likeCount}</span>}
                  </button>
                </div>
              </motion.div>
            ))}
          </div>

          {profile && showCompose && (
            <ComposeBox
              profile={profile}
              onPost={handleNewReply}
              parentId={post.id}
              replyingTo={post.author?.username}
              onCancelReply={() => setShowCompose(false)}
              autoFocus
            />
          )}

          {profile && !showCompose && (
            <button
              onClick={() => setShowCompose(true)}
              className="text-[#8B5CF6] text-xs font-medium hover:text-[#A78BFA] transition-colors cursor-pointer py-1"
            >
              + Responder
            </button>
          )}
        </>
      )}
    </div>
  );
}

// ─── Post Card ────────────────────────────────────────────────────────────────

function PostCard({
  post,
  profile,
  code,
  token,
  onLike,
}: {
  post: Post;
  profile: SocialProfile | null;
  code: string;
  token: string;
  onLike: (postId: string) => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const [showReplies, setShowReplies] = useState(false);
  const MAX = 280;
  const longText = (post.content?.length ?? 0) > MAX;

  return (
    <motion.article
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-[#131722] rounded-2xl border border-white/5 p-4 hover:border-white/8 transition-colors"
    >
      <div className="flex items-start gap-3 mb-3">
        <Avatar photo_url={post.author?.photo_url} username={post.author?.username ?? "?"} size={38} />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-[#F3F4F6] text-sm font-semibold truncate">{post.author?.username ?? "Usuario"}</span>
            {post.isMe && <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-[#8B5CF6]/15 text-[#8B5CF6] uppercase tracking-wide shrink-0">tú</span>}
          </div>
          <span className="text-[#4B5563] text-[11px]">{timeAgo(post.created_at)}</span>
        </div>
      </div>

      {post.content && (
        <div className="mb-3 pl-0.5">
          <p className="text-[#E5E7EB] text-sm leading-relaxed whitespace-pre-wrap break-words">
            {longText && !expanded ? post.content.slice(0, MAX) + "…" : post.content}
          </p>
          {longText && (
            <button onClick={() => setExpanded((e) => !e)} className="text-[#8B5CF6] text-xs font-medium mt-1 hover:text-[#A78BFA] transition-colors cursor-pointer">
              {expanded ? "Mostrar menos" : "Ver más"}
            </button>
          )}
        </div>
      )}

      {post.image_url && (
        <div className="mb-3 rounded-xl overflow-hidden bg-[#0D0F14]">
          <img src={post.image_url} alt="imagen del post" className="w-full max-h-[360px] object-cover" />
        </div>
      )}

      <div className="flex items-center gap-4 pt-2 border-t border-white/4">
        <button
          onClick={() => onLike(post.id)}
          className={`flex items-center gap-1.5 text-xs font-medium transition-colors cursor-pointer group ${post.likedByMe ? "text-[#EF4444]" : "text-[#4B5563] hover:text-[#EF4444]"}`}
        >
          <svg width="15" height="15" viewBox="0 0 24 24" fill={post.likedByMe ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="transition-transform group-active:scale-125">
            <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
          </svg>
          {post.likeCount > 0 && <span className="tabular-nums">{post.likeCount}</span>}
        </button>

        <button
          onClick={() => setShowReplies((v) => !v)}
          className={`flex items-center gap-1.5 text-xs font-medium transition-colors cursor-pointer ${showReplies ? "text-[#8B5CF6]" : "text-[#4B5563] hover:text-[#8B5CF6]"}`}
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
          </svg>
          {post.replyCount > 0
            ? <span className="tabular-nums">{post.replyCount}</span>
            : <span>Responder</span>
          }
        </button>
      </div>

      <AnimatePresence>
        {showReplies && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.2 }}
          >
            <ReplyThread post={post} profile={profile} code={code} token={token} />
          </motion.div>
        )}
      </AnimatePresence>
    </motion.article>
  );
}

// ─── Main Feed Page ───────────────────────────────────────────────────────────

export default function FeedPage() {
  const [code, setCode] = useState<string | null>(null);
  const [token, setToken] = useState<string | null>(null);

  const [profile, setProfile] = useState<SocialProfile | null | undefined>(undefined);
  const [posts, setPosts] = useState<Post[]>([]);
  const [loadingPosts, setLoadingPosts] = useState(true);
  const [showProfileModal, setShowProfileModal] = useState(false);
  const [editingProfile, setEditingProfile] = useState(false);

  useEffect(() => {
    const c = getLastTournamentCode();
    const t = c ? getMemberToken(c) : null;
    setCode(c);
    setToken(t);
  }, []);

  const fetchProfile = useCallback(async () => {
    if (!code || !token) return;
    try {
      const res = await fetch(`/api/tournaments/${code}/social/profile`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const { profile: p } = await res.json();
        setProfile(p);
        if (!p) setShowProfileModal(true);
      }
    } catch { setProfile(null); }
  }, [code, token]);

  const fetchPosts = useCallback(async () => {
    if (!code || !token) return;
    setLoadingPosts(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/social/posts`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const { posts: p } = await res.json();
        setPosts(p ?? []);
      }
    } finally { setLoadingPosts(false); }
  }, [code, token]);

  useEffect(() => {
    if (code && token) {
      fetchProfile();
      fetchPosts();
    }
  }, [fetchProfile, fetchPosts, code, token]);

  // ── Realtime: nuevos posts en tiempo real ────────────────────────────────
  useEffect(() => {
    if (!code || !token) return;

    const supabase = getBrowserClient();

    const channel = supabase
      .channel(`feed:${code}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "posts" },
        async (payload) => {
          // Solo top-level posts se agregan al feed principal
          if (payload.new?.parent_id) return;

          // Refetch para obtener datos enriquecidos (autor, likes, etc.)
          try {
            const res = await fetch(`/api/tournaments/${code}/social/posts`, {
              headers: { Authorization: `Bearer ${token}` },
            });
            if (res.ok) {
              const { posts: latest } = await res.json();
              setPosts((prev) => {
                const existingIds = new Set(prev.map((p) => p.id));
                const newPosts = (latest as Post[]).filter((p) => !existingIds.has(p.id));
                if (newPosts.length === 0) return prev;
                return [...newPosts, ...prev];
              });
            }
          } catch { /* silent fail */ }
        }
      )
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [code, token]);

  const handleLike = useCallback(
    async (postId: string) => {
      if (!code || !token) return;
      setPosts((prev) =>
        prev.map((p) =>
          p.id === postId
            ? { ...p, likedByMe: !p.likedByMe, likeCount: p.likedByMe ? p.likeCount - 1 : p.likeCount + 1 }
            : p
        )
      );
      try {
        await fetch(`/api/tournaments/${code}/social/posts/${postId}/like`, {
          method: "POST",
          headers: { Authorization: `Bearer ${token}` },
        });
      } catch {
        setPosts((prev) =>
          prev.map((p) =>
            p.id === postId
              ? { ...p, likedByMe: !p.likedByMe, likeCount: p.likedByMe ? p.likeCount - 1 : p.likeCount + 1 }
              : p
          )
        );
      }
    },
    [code, token]
  );

  const handleNewPost = (post: Post) => { setPosts((prev) => [post, ...prev]); };

  const handleProfileSaved = (saved: SocialProfile) => {
    setProfile(saved);
    setShowProfileModal(false);
    setEditingProfile(false);
  };

  if (!code || !token) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-[#9CA3AF] text-sm">Sin sesión activa.</p>
      </div>
    );
  }

  if (profile === undefined) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <div className="w-8 h-8 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
          <p className="text-[#9CA3AF] text-sm">Cargando feed…</p>
        </div>
      </div>
    );
  }

  return (
    <>
      <AnimatePresence>
        {(showProfileModal || editingProfile) && (
          <ProfileSetupModal
            existing={editingProfile ? profile : null}
            onSave={handleProfileSaved}
            onClose={editingProfile ? () => setEditingProfile(false) : undefined}
          />
        )}
      </AnimatePresence>

      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.3 }}
        className="max-w-xl mx-auto px-3 sm:px-4 py-5 sm:py-8"
      >
        <div className="flex items-center justify-between mb-5 sm:mb-6">
          <div>
            <p className="text-[#9CA3AF] text-[10px] sm:text-xs uppercase tracking-widest font-medium mb-0.5">Red Social</p>
            <h1 className="text-[#F3F4F6] text-xl sm:text-2xl font-bold tracking-tight">Feed</h1>
          </div>
          {profile && (
            <button
              onClick={() => setEditingProfile(true)}
              className="flex items-center gap-2 px-3 py-2 rounded-xl bg-[#131722] border border-white/5 hover:border-[#8B5CF6]/30 text-[#9CA3AF] hover:text-[#F3F4F6] text-xs font-medium transition-all cursor-pointer"
              title="Editar perfil social"
            >
              <Avatar photo_url={profile.photo_url} username={profile.username} size={22} />
              <span className="truncate max-w-[80px]">@{profile.username}</span>
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/>
              </svg>
            </button>
          )}
        </div>

        {profile && <ComposeBox profile={profile} onPost={handleNewPost} />}

        {!profile && (
          <div className="bg-[#131722] rounded-2xl border border-[#8B5CF6]/20 p-5 mb-5 flex items-center gap-4">
            <div className="w-10 h-10 rounded-xl bg-[#8B5CF6]/10 flex items-center justify-center shrink-0">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-[#F3F4F6] text-sm font-semibold">Configura tu perfil</p>
              <p className="text-[#9CA3AF] text-xs">Elige tu nombre y foto para participar en el feed</p>
            </div>
            <button onClick={() => setShowProfileModal(true)} className="px-3 py-1.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white text-xs font-bold transition-colors cursor-pointer shrink-0">
              Configurar
            </button>
          </div>
        )}

        {loadingPosts ? (
          <div className="flex items-center justify-center py-16">
            <div className="w-6 h-6 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
          </div>
        ) : posts.length === 0 ? (
          <div className="text-center py-16">
            <div className="w-12 h-12 rounded-2xl bg-[#131722] border border-white/5 flex items-center justify-center mx-auto mb-3">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#4B5563" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
            </div>
            <p className="text-[#4B5563] text-sm">Nadie ha publicado todavía.</p>
            <p className="text-[#3B4252] text-xs mt-1">¡Sé el primero en publicar algo!</p>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {posts.map((post, i) => (
              <motion.div key={post.id} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.03 }}>
                <PostCard post={post} profile={profile} code={code} token={token} onLike={handleLike} />
              </motion.div>
            ))}
          </div>
        )}
      </motion.div>
    </>
  );
}
