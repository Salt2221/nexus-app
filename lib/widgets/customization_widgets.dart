import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../services/customization_service.dart';

// ════════════════════════════════════════════
// Кастомизируемые UI-виджеты для NEXUS
// ════════════════════════════════════════════

class CustomizedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  const CustomizedAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final service = CustomizationService.instance;
    return AppBar(
      title: Text(title, style: TextStyle(
        fontSize: service.appBarFontSize,
        fontWeight: FontWeight.bold,
      )),
      backgroundColor: service.primaryColor.withOpacity(0.9),
      foregroundColor: Colors.white,
      elevation: 0,
      leading: leading,
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class CustomizedBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final DateTime? timestamp;

  const CustomizedBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final service = CustomizationService.instance;
    final color = isMe ? service.myBubbleColor : service.theirBubbleColor;
    final gradient = isMe ? service.myBubbleGradient : service.theirBubbleGradient;
    final shadow = isMe ? service.myBubbleShadow : service.theirBubbleShadow;
    final border = isMe ? service.myBubbleBorder : service.theirBubbleBorder;

    BoxDecoration decoration;
    if (gradient != null) {
      decoration = BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(18).copyWith(
          bottomRight: isMe ? const Radius.circular(4) : null,
          bottomLeft: !isMe ? const Radius.circular(4) : null,
        ),
        boxShadow: shadow != null ? [BoxShadow(
          color: shadow.withOpacity(0.3),
          blurRadius: 6,
          offset: const Offset(0, 2),
        )] : null,
      );
    } else {
      decoration = BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18).copyWith(
          bottomRight: isMe ? const Radius.circular(4) : null,
          bottomLeft: !isMe ? const Radius.circular(4) : null,
        ),
        border: border != null ? Border.all(color: border, width: 1) : null,
        boxShadow: shadow != null ? [BoxShadow(
          color: shadow.withOpacity(0.3),
          blurRadius: 6,
          offset: const Offset(0, 2),
        )] : null,
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: decoration,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(text, style: TextStyle(
              color: Colors.white,
              fontSize: service.messageFontSize,
            )),
            if (timestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${timestamp!.hour}:${timestamp!.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CustomizedChatBackground extends StatelessWidget {
  final Widget child;

  const CustomizedChatBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final service = CustomizationService.instance;

    if (service.backgroundImage != null) {
      return Stack(
        children: [
          Positioned.fill(
            child: Image.file(
              service.backgroundImage!,
              fit: BoxFit.cover,
              opacity: AlwaysStoppedAnimation(service.backgroundOpacity),
            ),
          ),
          if (service.backgroundBlur > 0)
            Positioned.fill(
              child: BackdropFilter(
                filter: _blur(service.backgroundBlur),
                child: Container(color: Colors.transparent),
              ),
            ),
          child,
        ],
      );
    }

    if (service.backgroundGradient != null) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: service.backgroundGradient!),
        ),
        child: child,
      );
    }

    return Container(
      color: service.backgroundOpacity > 0
          ? Colors.black.withOpacity(service.backgroundOpacity)
          : null,
      child: child,
    );
  }

  ui.ImageFilter _blur(double sigma) => ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
}

class CustomizedAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;

  const CustomizedAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final service = CustomizationService.instance;
    if (!service.showAvatars) return const SizedBox.shrink();

    if (imageUrl != null) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(imageUrl!),
      );
    }

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: service.primaryColor,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}
