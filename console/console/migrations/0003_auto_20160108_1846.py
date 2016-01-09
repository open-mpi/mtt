# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('console', '0002_auto_20160108_1845'),
    ]

    operations = [
        migrations.RenameField(
            model_name='node',
            old_name='nodeblade',
            new_name='blade',
        ),
    ]
