<?xml version="1.0" ?>

<!--
    <interface type='network'>
        <source network='vnetOVS' portgroup='HOST_RG_CLOUD_CANONICAL_CORE'/>
        <model type='virtio'/>
        </interface>

-->

<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output omit-xml-declaration="yes" indent="yes"/>

    <xsl:template match="node()|@*">
    <xsl:copy>
        <xsl:apply-templates select="node()|@*"/>
    </xsl:copy>
</xsl:template>

<xsl:template match="/domain/devices">
    <xsl:copy>
        <xsl:apply-templates select="node()|@*"/>
        %{ for interface in interfaces ~}
        <xsl:element name="interface">
            <xsl:attribute name="type">network</xsl:attribute>
            <xsl:element name="source">
                <xsl:attribute name="network">${interface.network}</xsl:attribute>
                <xsl:attribute name="portgroup">${interface.portgroup}</xsl:attribute>
            </xsl:element>
            <xsl:element name="model">
                <xsl:attribute name="type">${interface.type}</xsl:attribute>
            </xsl:element>
        </xsl:element>
        %{ endfor ~}
    </xsl:copy>
</xsl:template>

</xsl:stylesheet>
