import 'package:flutter/material.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';
import 'package:ainas_frontend/services/api_service.dart';

/// Industry Standard: Logic is moved from the Widget to a Controller/ChangeNotifier.
class FileBrowserController extends ChangeNotifier {
  final ApiService _api = ApiService();
  
  List<String> pathStack = [""];
  List<FileItem> items = [];
  bool isLoading = false;
  int sortColumnIndex = 0;
  bool sortAscending = true;

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();
    try {
      items = await _api.listFiles(pathStack.last);
      _sortItems();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void updateSort(int index, bool ascending) {
    sortColumnIndex = index;
    sortAscending = ascending;
    _sortItems();
    notifyListeners();
  }

  void _sortItems() {
    items.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      
      int cmp = 0;
      switch (sortColumnIndex) {
        case 0: cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase()); break;
        case 1: cmp = a.size.compareTo(b.size); break;
        case 3: cmp = a.updatedAt.compareTo(b.updatedAt); break;
      }
      return sortAscending ? cmp : -cmp;
    });
  }

  void pushPath(String folderName) {
    pathStack.add(pathStack.last.isEmpty ? folderName : "${pathStack.last}/$folderName");
    refresh();
  }
}