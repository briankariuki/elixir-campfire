// Composer drafts: the unsent text of a room's composer, kept in localStorage under
// "composer-draft-<roomId>" (like the original Campfire). localStorage can be unavailable or full
// (private mode, quota), so every access ignores errors.

const key = roomId => `composer-draft-${roomId}`

export function loadDraft(roomId) {
  try {
    return localStorage.getItem(key(roomId)) || ""
  } catch (_error) {
    return ""
  }
}

// An empty (or whitespace-only) draft removes the entry
export function saveDraft(roomId, value) {
  try {
    if (value.trim() === "") localStorage.removeItem(key(roomId))
    else localStorage.setItem(key(roomId), value)
  } catch (_error) {
    // ignore
  }
}

export function clearDraft(roomId) {
  try {
    localStorage.removeItem(key(roomId))
  } catch (_error) {
    // ignore
  }
}
