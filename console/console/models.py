from django.db import models
from django_enumfield import enum

# Stage-related Models
class Option(models.Model):
    name = models.CharField(max_length=200)
    value = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class StageType(enum.Enum):
    SETUP = 0
    DVMSTART = 1
    PROVISION = 2
    FWFLASH = 3
    BIOSFLASH = 4
    PKGLOAD = 5
    EXECOPTIONS = 6
    GETTEST = 7
    BUILDTEST = 8
    RUNTEST = 9
    REPORT = 10

class Stage(models.Model):
    name = models.CharField(max_length=200)
    sttype = enum.EnumField(StageType)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

# Inventory-related Models
class OSType(models.Model):
    name = models.CharField(max_length=200)
    version = models.CharField(max_length=200, default="N/A")
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class SWPackage(models.Model):
    name = models.CharField(max_length=200)
    version = models.CharField(max_length=200, default="N/A")
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class Image(models.Model):
    name = models.CharField(max_length=200)
    created = models.DateTimeField('date created')
    modified = models.DateTimeField('last modified')
    base_OS = models.ForeignKey(OSType)
    packages = models.ManyToManyField(SWPackage)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class CPUDieType(models.Model):
    name = models.CharField(max_length=200)
    vendor = models.CharField(max_length=200)
    model = models.CharField(max_length=200)
    family = models.PositiveIntegerField('cpu family')
    model_number = models.PositiveIntegerField('model#')
    version = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class CPUDie(models.Model):
    dietype = models.ForeignKey(CPUDieType)
    serial = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.serial

class MemDieType(models.Model):
    name = models.CharField(max_length=200)
    vendor = models.CharField(max_length=200)
    model = models.CharField(max_length=200)
    model_number = models.PositiveIntegerField('model#')
    version = models.CharField(max_length=200)
    capacity = models.PositiveIntegerField('Megabytes')
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class MemDie(models.Model):
    dietype = models.ForeignKey(MemDieType)
    serial = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.serial

class PackageType(models.Model):
    name = models.CharField(max_length=200)
    vendor = models.CharField(max_length=200)
    model = models.CharField(max_length=200)
    version = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class Package(models.Model):
    pkgtype = models.ForeignKey(PackageType)
    cpus = models.ManyToManyField(CPUDie)
    ipm = models.ManyToManyField(MemDie)
    serial = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.serial

class NetworkType(models.Model):
    name = models.CharField(max_length=200)
    vendor = models.CharField(max_length=200)
    model = models.CharField(max_length=200)
    version = models.CharField(max_length=200)
    bw = models.FloatField('Mbits/sec')
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class NetworkPort(models.Model):
    name = models.CharField(max_length=32)
    mac_address = models.CharField(max_length=128)
    net_address = models.CharField(max_length=128)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class NIC(models.Model):
    name = models.CharField(max_length=200)
    nettype = models.ForeignKey(NetworkType)
    serial = models.CharField(max_length=200)
    firmware_version = models.CharField(max_length=200)
    firmware_release = models.DateTimeField('Firmware release date')
    ports = models.ManyToManyField(NetworkPort)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class BladeMgrType(models.Model):
    name = models.CharField(max_length=200)
    vendor = models.CharField(max_length=200)
    model = models.CharField(max_length=200)
    model_number = models.PositiveIntegerField('model#')
    version = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class BladeMgr(models.Model):
    bldmgrtype = models.ForeignKey(BladeMgrType)
    serial = models.CharField(max_length=200)
    bios = models.CharField(max_length=200)
    bios_release = models.DateTimeField('BIOS release date')
    def __unicode__(self):              #  __str__ on Python 3
        return self.serial

class BladeType(models.Model):
    name = models.CharField(max_length=200)
    vendor = models.CharField(max_length=200)
    model = models.CharField(max_length=200)
    model_number = models.PositiveIntegerField('model#')
    version = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class Blade(models.Model):
    bladetype = models.ForeignKey(BladeType)
    serial = models.CharField(max_length=200)
    pkgs = models.ManyToManyField(Package)
    bldmgr = models.ForeignKey(BladeMgr)
    nics = models.ManyToManyField(NIC)          # NICs in blade, if applicable
    def __unicode__(self):              #  __str__ on Python 3
        return self.serial

class ConnectorType(enum.Enum):
    RJ45 = 0
    FIBER = 1

class SwitchType(models.Model):
    name = models.CharField(max_length=200)
    vendor = models.CharField(max_length=200)
    model = models.CharField(max_length=200)
    model_number = models.PositiveIntegerField('model#')
    version = models.CharField(max_length=200)
    nports =models.PositiveIntegerField('#ports')
    connector = enum.EnumField(ConnectorType)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class Switch(models.Model):
    switchtype = models.ForeignKey(SwitchType)
    serial = models.CharField(max_length=200)
    fw = models.CharField(max_length=200)
    fw_release = models.DateTimeField('FW release date')
    def __unicode__(self):              #  __str__ on Python 3
        return self.serial

class SwitchBladeType(models.Model):
    name = models.CharField(max_length=200)
    vendor = models.CharField(max_length=200)
    model = models.CharField(max_length=200)
    model_number = models.PositiveIntegerField('model#')
    version = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class SwitchBlade(models.Model):
    switchbladetype = models.ForeignKey(SwitchBladeType)
    serial = models.CharField(max_length=200)
    fw = models.CharField(max_length=200)
    fw_release = models.DateTimeField('FW release date')
    switches = models.ManyToManyField(Switch)
    def __unicode__(self):              #  __str__ on Python 3
        return self.serial

class ChassisMgrType(models.Model):
    name = models.CharField(max_length=200)
    vendor = models.CharField(max_length=200)
    model = models.CharField(max_length=200)
    model_number = models.PositiveIntegerField('model#')
    version = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class ChassisMgr(models.Model):
    chmgrtype = models.ForeignKey(ChassisMgrType)
    serial = models.CharField(max_length=200)
    bios = models.CharField(max_length=200)
    bios_release = models.DateTimeField('BIOS release date')
    def __unicode__(self):              #  __str__ on Python 3
        return self.serial

class ChassisType(models.Model):
    name = models.CharField(max_length=200)
    vendor = models.CharField(max_length=200)
    model = models.CharField(max_length=200)
    model_number = models.PositiveIntegerField('model#')
    version = models.CharField(max_length=200)
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class Chassis(models.Model):
    chtype = models.ForeignKey(ChassisType)
    serial = models.CharField(max_length=200)
    blades = models.ManyToManyField(Blade)
    chmgr = models.ForeignKey(ChassisMgr)
    nics = models.ManyToManyField(NIC)          # NICs in chassis, if applicable
    def __unicode__(self):              #  __str__ on Python 3
        return self.serial

class NodeType(enum.Enum):
    COMPUTE = 0
    IO = 1
    SYSTEM_MGMT = 2

class Node(models.Model):
    name = models.CharField(max_length=200)     # hostname
    role = enum.EnumField(NodeType)
    booted = models.DateTimeField('last booted')
    uptime = models.DateTimeField('uptime')
    image = models.ForeignKey(Image)            # image provisioned on this node
    blade = models.ForeignKey(Blade)            # blade housing this node, if applicable
    pkg = models.ForeignKey(Package)            # package containing this node, if applicable
    cpus = models.ForeignKey(CPUDie)            # die in package, if applicable
    nics = models.ManyToManyField(NIC)          # NICs attached to node, if applicable
    bios = models.CharField(max_length=200, default="N/A")
    bios_release = models.DateTimeField('BIOS release date')
    def __unicode__(self):              #  __str__ on Python 3
        return self.name

class Rack(models.Model):
    nodes = models.ManyToManyField(Node)            # rack-mountable servers
    chassis = models.ManyToManyField(Chassis)       # chassis-based nodes


# Overall test definition
