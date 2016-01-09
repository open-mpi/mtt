# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('console', '0001_initial'),
    ]

    operations = [
        migrations.RenameField(
            model_name='node',
            old_name='blade',
            new_name='nodeblade',
        ),
    ]
