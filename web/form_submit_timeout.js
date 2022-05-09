$(document).ready(function () {
    $('form.submit_timeout').submit(function (event) {
        var current_form = $(this);
        if (! current_form.data('timeout_pending')) {
            current_form.data('timeout_pending', 'yes');
            current_form.css({'opacity': 0.5});

            setTimeout(function () {
                current_form.removeData('timeout_pending');
                current_form.css({'opacity': 1.0});
            }, 10000);

            return true;
        }

        alert('This form has already been submitted.\nPlease wait for the server to process your request.');
        event.preventDefault();
    });
});
