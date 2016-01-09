from django.contrib import admin

# Register your models here.
from django.contrib import admin

from .models import *

class ImageAdmin(admin.ModelAdmin):
    fieldsets = [
        (None,               {'fields': ['name']}),
        ('Date information', {'fields': ['created', 'modified']})
    ]

admin.site.register(Image, ImageAdmin)

# Register the rest of the classes
admin.site.register(Option)
admin.site.register(Stage)
admin.site.register(OSType)
admin.site.register(SWPackage)
admin.site.register(CPUDieType)
admin.site.register(CPUDie)
admin.site.register(MemDieType)
admin.site.register(MemDie)
admin.site.register(PackageType)
admin.site.register(Package)
admin.site.register(NetworkType)
admin.site.register(NetworkPort)
admin.site.register(NIC)
admin.site.register(BladeMgrType)
admin.site.register(BladeMgr)
admin.site.register(BladeType)
admin.site.register(Blade)
admin.site.register(SwitchType)
admin.site.register(Switch)
admin.site.register(SwitchBladeType)
admin.site.register(SwitchBlade)
admin.site.register(ChassisMgrType)
admin.site.register(ChassisMgr)
admin.site.register(ChassisType)
admin.site.register(Chassis)
admin.site.register(Node)
admin.site.register(Rack)
