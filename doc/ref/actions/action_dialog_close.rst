.. highlight:: django
.. include:: meta-dialog_close.rst
.. seealso:: actions :ref:`action-dialog_open` and :ref:`action-dialog`.

Closes the currently open dialog. When there is no dialog open then nothing happens.

Example::

   {% button text="cancel" action={dialog_close} %}

This button closes any open dialog when clicked.
