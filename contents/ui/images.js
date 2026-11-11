/*
    Which files are images and how the sorted orders arrange them, shared
    by the slideshow (main.qml, SpanState.qml) and the settings page's
    thumbnail grid (FolderImages.qml), so the grid lists the files the
    slideshow shows, in the slideshow's order.
*/
.pragma library

// For FolderListModel.nameFilters, with caseSensitive: false rather than
// each extension twice: the doubled list still missed mixed-case spellings
// like ".JpEg" that come out of some cameras and editors.
var nameFilters = ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp"];

// Sort comparator for SlideshowOrder 1 = A to Z, 2 = Z to A, 3 = date
// modified (newest first), 4 = date modified (oldest first). a and b are
// { name: lower-case file name, time: modified, in ms, url }. Ties fall
// back to the URL, so the order is total and the same on every screen.
function compare(order, a, b) {
    var c = 0;
    if (order === 1 || order === 2) {
        c = a.name.localeCompare(b.name);
        if (order === 2) {
            c = -c;
        }
    } else if (order === 3) {
        c = b.time - a.time;
    } else if (order === 4) {
        c = a.time - b.time;
    }
    return c !== 0 ? c : (a.url < b.url ? -1 : (a.url > b.url ? 1 : 0));
}
