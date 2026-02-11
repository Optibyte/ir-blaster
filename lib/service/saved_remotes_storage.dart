class SavedRemotesStorage {
  static final List<String> savedBrands = [];

  /// Adds a brand to the saved list if it's not already present
  static void addBrand(String brand) {
    if (!savedBrands.contains(brand)) {
      savedBrands.add(brand);
    }
  }

  /// Checks if any remotes are saved
  static bool hasSavedRemotes() => savedBrands.isNotEmpty;

  /// Optionally: Clear all saved remotes (useful for testing)
  static void clear() {
    savedBrands.clear();
  }

  /// Optionally: Remove a specific brand
  static void removeBrand(String brand) {
    savedBrands.remove(brand);
  }

  static void loadSavedBrands() {}
}
