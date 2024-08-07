$(document).ready(function () {
    $('a.copy_text').on('click', function (event) {
        var target = $(event.target);
        var copy_text = target.data('copy_text');
        var html_content = target.html();
        navigator.clipboard.writeText(copy_text).then(function() {
            target.html('&check;');
        }, function() {
            target.html('&cross;');
        });
        setTimeout(function () {
            target.html(html_content);
        }, 2000);
        event.preventDefault();
    });
});
