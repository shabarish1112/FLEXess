# Phase 15 Riverpod sync refresh

The explicit development refresh provider requires the currently selected account store, fetches bounded pages, applies them transactionally, and invalidates the diary family after cursor advancement. Today, Diary and Nutrition read that family. Guest mode does not schedule sync. An already-open Progress route uses a separate history query and is outside this refresh path.
