enum ShelfTarget {
  fiveStar, // users/{uid}.fiveStarKeys  + userTasteProfiles.fiveStars
  disliked, // users/{uid}.dislikedKeys + userTasteProfiles.lowRatings
  favorites, // users/{uid}.favoritesKeys
  watchlist, // users/{uid}.watchlistKeys
}
