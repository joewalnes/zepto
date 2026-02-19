======================
reStructuredText Guide
======================

Introduction
============

This document demonstrates **reStructuredText** syntax for highlighting.
reStructuredText is used by Sphinx_ for Python documentation.

Basic Formatting
----------------

Text can be *emphasized*, **strongly emphasized**, or use ``inline code``.
This is a `hyperlink <https://example.com>`_ and a standalone link:
https://example.com.

A footnote reference [1]_ and a citation reference [CIT2024]_.

Lists
-----

Bullet list:

- First item
- Second item with *emphasis*
- Third item

  - Nested item
  - Another nested item

Numbered list:

1. First step
2. Second step
3. Third step

#. Auto-numbered
#. Items

Definition list:

Term 1
    Definition of term 1.

Term 2
    Definition of term 2, which can span
    multiple lines.

Directives
==========

.. note::
   This is a note admonition.

.. warning::
   Be careful with this operation!

.. code-block:: python

   def fibonacci(n):
       """Calculate fibonacci number."""
       if n <= 1:
           return n
       return fibonacci(n - 1) + fibonacci(n - 2)

.. image:: images/logo.png
   :alt: Project Logo
   :width: 200px
   :align: center

.. table:: Comparison Table
   :widths: auto

   ======  =====  ======
   Name    Score  Grade
   ======  =====  ======
   Alice   95     A
   Bob     82     B
   Carol   71     C
   ======  =====  ======

Field Lists
-----------

:Author: Jane Doe
:Version: 2.0
:Date: 2024-01-15
:Status: Draft
:License: MIT

Roles and Interpreted Text
--------------------------

See :ref:`introduction` for more details.
The :func:`fibonacci` function is defined in :mod:`math_utils`.
See :doc:`api/reference` for the full API.
Use :command:`make html` to build the docs.

This is :math:`E = mc^2` inline math.

Cross-references: :pep:`8`, :rfc:`2616`.

Literal Blocks
--------------

A paragraph ending with double colon::

    This is a literal block.
    It preserves formatting and whitespace.
    No **markup** is processed here.

Substitutions
-------------

|project| is version |version|.

.. |project| replace:: MyProject
.. |version| replace:: 1.0.0

Tables
------

+------------+----------+----------+
| Header 1   | Header 2 | Header 3 |
+============+==========+==========+
| Row 1      | Cell     | Cell     |
+------------+----------+----------+
| Row 2      | Cell     | Cell     |
+------------+----------+----------+

Comments
--------

.. This is a comment that won't appear in output.

..
   This is also a comment block
   spanning multiple lines.

Footnotes
---------

.. [1] This is footnote 1.
.. [CIT2024] Citation reference, 2024.
.. _Sphinx: https://www.sphinx-doc.org/

Indices and Tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
