-- MySQL dump 10.13  Distrib 5.5.40, for debian-linux-gnu (x86_64)
--
-- Host: nbn-l8-dev2-os-8    Database: neutron_ml2
-- ------------------------------------------------------
-- Server version	5.5.40-0ubuntu0.14.04.1-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `securitygrouprules`
--

DROP TABLE IF EXISTS `securitygrouprules`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `securitygrouprules` (
  `tenant_id` varchar(255) DEFAULT NULL,
  `id` varchar(36) NOT NULL,
  `security_group_id` varchar(36) NOT NULL,
  `remote_group_id` varchar(36) DEFAULT NULL,
  `direction` enum('ingress','egress') DEFAULT NULL,
  `ethertype` varchar(40) DEFAULT NULL,
  `protocol` varchar(40) DEFAULT NULL,
  `port_range_min` int(11) DEFAULT NULL,
  `port_range_max` int(11) DEFAULT NULL,
  `remote_ip_prefix` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `security_group_id` (`security_group_id`),
  KEY `remote_group_id` (`remote_group_id`),
  CONSTRAINT `securitygrouprules_ibfk_1` FOREIGN KEY (`security_group_id`) REFERENCES `securitygroups` (`id`) ON DELETE CASCADE,
  CONSTRAINT `securitygrouprules_ibfk_2` FOREIGN KEY (`remote_group_id`) REFERENCES `securitygroups` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed
