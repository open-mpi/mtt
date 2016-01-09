# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
    ]

    operations = [
        migrations.CreateModel(
            name='Blade',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('serial', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='BladeMgr',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('serial', models.CharField(max_length=200)),
                ('bios', models.CharField(max_length=200)),
                ('bios_release', models.DateTimeField(verbose_name=b'BIOS release date')),
            ],
        ),
        migrations.CreateModel(
            name='BladeMgrType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('vendor', models.CharField(max_length=200)),
                ('model', models.CharField(max_length=200)),
                ('model_number', models.PositiveIntegerField(verbose_name=b'model#')),
                ('version', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='BladeType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('vendor', models.CharField(max_length=200)),
                ('model', models.CharField(max_length=200)),
                ('model_number', models.PositiveIntegerField(verbose_name=b'model#')),
                ('version', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='Chassis',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('serial', models.CharField(max_length=200)),
                ('blades', models.ManyToManyField(to='console.Blade')),
            ],
        ),
        migrations.CreateModel(
            name='ChassisMgr',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('serial', models.CharField(max_length=200)),
                ('bios', models.CharField(max_length=200)),
                ('bios_release', models.DateTimeField(verbose_name=b'BIOS release date')),
            ],
        ),
        migrations.CreateModel(
            name='ChassisMgrType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('vendor', models.CharField(max_length=200)),
                ('model', models.CharField(max_length=200)),
                ('model_number', models.PositiveIntegerField(verbose_name=b'model#')),
                ('version', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='ChassisType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('vendor', models.CharField(max_length=200)),
                ('model', models.CharField(max_length=200)),
                ('model_number', models.PositiveIntegerField(verbose_name=b'model#')),
                ('version', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='CPUDie',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('serial', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='CPUDieType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('vendor', models.CharField(max_length=200)),
                ('model', models.CharField(max_length=200)),
                ('family', models.PositiveIntegerField(verbose_name=b'cpu family')),
                ('model_number', models.PositiveIntegerField(verbose_name=b'model#')),
                ('version', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='Image',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('created', models.DateTimeField(verbose_name=b'date created')),
                ('modified', models.DateTimeField(verbose_name=b'last modified')),
            ],
        ),
        migrations.CreateModel(
            name='MemDie',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('serial', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='MemDieType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('vendor', models.CharField(max_length=200)),
                ('model', models.CharField(max_length=200)),
                ('model_number', models.PositiveIntegerField(verbose_name=b'model#')),
                ('version', models.CharField(max_length=200)),
                ('capacity', models.PositiveIntegerField(verbose_name=b'Megabytes')),
            ],
        ),
        migrations.CreateModel(
            name='NetworkPort',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=32)),
                ('mac_address', models.CharField(max_length=128)),
                ('net_address', models.CharField(max_length=128)),
            ],
        ),
        migrations.CreateModel(
            name='NetworkType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('vendor', models.CharField(max_length=200)),
                ('model', models.CharField(max_length=200)),
                ('version', models.CharField(max_length=200)),
                ('bw', models.FloatField(verbose_name=b'Mbits/sec')),
            ],
        ),
        migrations.CreateModel(
            name='NIC',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('serial', models.CharField(max_length=200)),
                ('firmware_version', models.CharField(max_length=200)),
                ('firmware_release', models.DateTimeField(verbose_name=b'Firmware release date')),
                ('nettype', models.ForeignKey(to='console.NetworkType')),
                ('ports', models.ManyToManyField(to='console.NetworkPort')),
            ],
        ),
        migrations.CreateModel(
            name='Node',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('role', models.IntegerField(default=0)),
                ('booted', models.DateTimeField(verbose_name=b'last booted')),
                ('uptime', models.DateTimeField(verbose_name=b'uptime')),
                ('bios', models.CharField(default=b'N/A', max_length=200)),
                ('bios_release', models.DateTimeField(verbose_name=b'BIOS release date')),
                ('blade', models.ForeignKey(to='console.Blade')),
                ('cpus', models.ForeignKey(to='console.CPUDie')),
                ('image', models.ForeignKey(to='console.Image')),
                ('nics', models.ManyToManyField(to='console.NIC')),
            ],
        ),
        migrations.CreateModel(
            name='Option',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('value', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='OSType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('version', models.CharField(default=b'N/A', max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='Package',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('serial', models.CharField(max_length=200)),
                ('cpus', models.ManyToManyField(to='console.CPUDie')),
                ('ipm', models.ManyToManyField(to='console.MemDie')),
            ],
        ),
        migrations.CreateModel(
            name='PackageType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('vendor', models.CharField(max_length=200)),
                ('model', models.CharField(max_length=200)),
                ('version', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='Rack',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('chassis', models.ManyToManyField(to='console.Chassis')),
                ('nodes', models.ManyToManyField(to='console.Node')),
            ],
        ),
        migrations.CreateModel(
            name='Stage',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('sttype', models.IntegerField(default=0)),
            ],
        ),
        migrations.CreateModel(
            name='Switch',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('serial', models.CharField(max_length=200)),
                ('fw', models.CharField(max_length=200)),
                ('fw_release', models.DateTimeField(verbose_name=b'FW release date')),
            ],
        ),
        migrations.CreateModel(
            name='SwitchBlade',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('serial', models.CharField(max_length=200)),
                ('fw', models.CharField(max_length=200)),
                ('fw_release', models.DateTimeField(verbose_name=b'FW release date')),
            ],
        ),
        migrations.CreateModel(
            name='SwitchBladeType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('vendor', models.CharField(max_length=200)),
                ('model', models.CharField(max_length=200)),
                ('model_number', models.PositiveIntegerField(verbose_name=b'model#')),
                ('version', models.CharField(max_length=200)),
            ],
        ),
        migrations.CreateModel(
            name='SwitchType',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('vendor', models.CharField(max_length=200)),
                ('model', models.CharField(max_length=200)),
                ('model_number', models.PositiveIntegerField(verbose_name=b'model#')),
                ('version', models.CharField(max_length=200)),
                ('nports', models.PositiveIntegerField(verbose_name=b'#ports')),
                ('connector', models.IntegerField(default=0)),
            ],
        ),
        migrations.CreateModel(
            name='SWPackage',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('name', models.CharField(max_length=200)),
                ('version', models.CharField(default=b'N/A', max_length=200)),
            ],
        ),
        migrations.AddField(
            model_name='switchblade',
            name='switchbladetype',
            field=models.ForeignKey(to='console.SwitchBladeType'),
        ),
        migrations.AddField(
            model_name='switchblade',
            name='switches',
            field=models.ManyToManyField(to='console.Switch'),
        ),
        migrations.AddField(
            model_name='switch',
            name='switchtype',
            field=models.ForeignKey(to='console.SwitchType'),
        ),
        migrations.AddField(
            model_name='package',
            name='pkgtype',
            field=models.ForeignKey(to='console.PackageType'),
        ),
        migrations.AddField(
            model_name='node',
            name='pkg',
            field=models.ForeignKey(to='console.Package'),
        ),
        migrations.AddField(
            model_name='memdie',
            name='dietype',
            field=models.ForeignKey(to='console.MemDieType'),
        ),
        migrations.AddField(
            model_name='image',
            name='base_OS',
            field=models.ForeignKey(to='console.OSType'),
        ),
        migrations.AddField(
            model_name='image',
            name='packages',
            field=models.ManyToManyField(to='console.SWPackage'),
        ),
        migrations.AddField(
            model_name='cpudie',
            name='dietype',
            field=models.ForeignKey(to='console.CPUDieType'),
        ),
        migrations.AddField(
            model_name='chassismgr',
            name='chmgrtype',
            field=models.ForeignKey(to='console.ChassisMgrType'),
        ),
        migrations.AddField(
            model_name='chassis',
            name='chmgr',
            field=models.ForeignKey(to='console.ChassisMgr'),
        ),
        migrations.AddField(
            model_name='chassis',
            name='chtype',
            field=models.ForeignKey(to='console.ChassisType'),
        ),
        migrations.AddField(
            model_name='chassis',
            name='nics',
            field=models.ManyToManyField(to='console.NIC'),
        ),
        migrations.AddField(
            model_name='blademgr',
            name='bldmgrtype',
            field=models.ForeignKey(to='console.BladeMgrType'),
        ),
        migrations.AddField(
            model_name='blade',
            name='bladetype',
            field=models.ForeignKey(to='console.BladeType'),
        ),
        migrations.AddField(
            model_name='blade',
            name='bldmgr',
            field=models.ForeignKey(to='console.BladeMgr'),
        ),
        migrations.AddField(
            model_name='blade',
            name='nics',
            field=models.ManyToManyField(to='console.NIC'),
        ),
        migrations.AddField(
            model_name='blade',
            name='pkgs',
            field=models.ManyToManyField(to='console.Package'),
        ),
    ]
