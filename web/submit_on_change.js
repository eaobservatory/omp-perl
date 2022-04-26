$(document).ready(function () {
    $('select.submit_on_change').change(function () {
        $(this).closest('form').submit();
    });
});
