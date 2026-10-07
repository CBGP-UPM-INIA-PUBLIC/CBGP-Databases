// "Today" helpers for date boxes.
//
// Search (_search_date.erb): a tick box beside a date box. While it is ticked the date box
// is greyed out and not sent, so the search receives the word "today" - read by the server
// as the day the search is run.
//
// Data entry (_date.erb): a "Today" button that FILLS IN the date box with today's real date
// (the browser's own calendar day, so it is right in the user's time zone). What is saved is
// that date, never the word "today".
document.addEventListener('change', function(event) {
  var box = event.target;
  if (!box.matches || !box.matches('input[type="checkbox"][data-date-input]')) return;
  var date = document.getElementById(box.getAttribute('data-date-input'));
  if (date) date.disabled = box.checked;
});

document.addEventListener('click', function(event) {
  var button = event.target.closest ? event.target.closest('button[data-fill-today]') : null;
  if (!button) return;
  var wrapper = button.closest('.inputtype');
  var date = wrapper && wrapper.querySelector('input[type="date"]');
  if (!date) return;
  var now = new Date();
  var pad = function(n) { return (n < 10 ? '0' : '') + n; };
  date.value = now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate());
  date.dispatchEvent(new Event('input', { bubbles: true }));
  date.dispatchEvent(new Event('change', { bubbles: true }));
});
