// A second horizontal scrollbar ABOVE every wide table box (.table-scroll), kept in
// step with the one below it, so a long results table can be scrolled from either end
// without first travelling to the bottom of the page. The bar appears only while the
// table is actually wider than its box.
document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('.table-scroll').forEach(function(box) {
    var table = box.querySelector('table');
    if (!table) return;

    var top   = document.createElement('div');
    var inner = document.createElement('div');
    top.className = 'table-scroll-top';
    top.setAttribute('aria-hidden', 'true');   // a convenience only; the real one stays the accessible one
    top.appendChild(inner);
    box.parentNode.insertBefore(top, box);

    function sizeBar() {
      inner.style.width = box.scrollWidth + 'px';
      top.style.display = box.scrollWidth > box.clientWidth + 1 ? '' : 'none';
    }

    // Each bar drives the other; the flag stops the echo from bouncing back.
    var syncing = false;
    function follow(from, to) {
      from.addEventListener('scroll', function() {
        if (syncing) { syncing = false; return; }
        syncing = true;
        to.scrollLeft = from.scrollLeft;
      });
    }
    follow(top, box);
    follow(box, top);

    sizeBar();
    window.addEventListener('resize', sizeBar);
    window.addEventListener('load', sizeBar);
    if (window.ResizeObserver) new ResizeObserver(sizeBar).observe(table);
  });
});
